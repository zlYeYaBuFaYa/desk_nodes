using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Threading;
using DeskNodes.App.Interop;
using DeskNodes.Core.Domain;
using DeskNodes.Core.Presentation;

namespace DeskNodes.App.Views;

internal partial class ToolbarWindow : Window
{
    private readonly AppCoordinator app;
    private ToolbarIdleMachine idle = new();
    private readonly DispatcherTimer wake = new();
    private readonly DispatcherTimer frames = new() { Interval = TimeSpan.FromMilliseconds(16) };
    private readonly MonotonicTimeline timeline;
    private TimeSpan Now => timeline.Elapsed;
    private bool pressed, dragging, menuOpen, animating, round, externalDrag;
    private PointD downPixels;
    private RectD safe;
    private ScreenInfo safeScreen = null!;
    private PointD grabOffset;
    private readonly DispatcherTimer dragWatch = new() { Interval = TimeSpan.FromMilliseconds(20) };
    private ScreenInfo screen = null!;
    private HomePosition? projected;
    private FrameworkElement? grip;
    private long generation;
    private Action<double>? frame;
    private TimeSpan started;
    private double duration;
    private Action? finished;
    public ToolbarWindow(AppCoordinator app)
    {
        this.app = app;
        timeline = new(app.TimeProvider);
        InitializeComponent();
        DataContext = model;
        theme = ((App)Application.Current).Theme;
        theme.Changed += ThemeChanged;
        entranceHit.PlacementTarget = this;
        stackHint.PlacementTarget = this;
        entranceHit.Opened += PlacePopupBehindActiveApplications;
        stackHint.Opened += PlacePopupBehindActiveApplications;
        AllowDrop = true;
        DragEnter += (_, _) =>
        {
            externalDrag = true;
            Tick();
        };
        DragLeave += (_, _) => EndExternalDrag();
        Drop += (_, _) => EndExternalDrag();
        Loaded += (_, _) => Place(Bounds);
        SourceInitialized += (_, _) =>
        {
            var handle = new WindowInteropHelper(this).Handle;
            NativeMethods.SetWindowLongPtr(handle, NativeMethods.GWL_EXSTYLE,
                NativeMethods.GetWindowLongPtr(handle, NativeMethods.GWL_EXSTYLE) | NativeMethods.WS_EX_TOOLWINDOW | NativeMethods.WS_EX_NOACTIVATE);
            HwndSource.FromHwnd(handle)?.AddHook(Message);
            ApplyMaterial();
        };
        wake.Tick += (_, _) => Tick();
        frames.Tick += (_, _) => RenderFrame();
        dragWatch.Tick += (_, _) =>
        {
            if ((NativeMethods.GetAsyncKeyState(NativeMethods.VK_ESCAPE) & 0x8000) != 0) CancelDrag();
        };
        MouseEnter += (_, _) => Tick();
        MouseLeave += (_, _) => Tick();
        PreviewMouseLeftButtonDown += Down;
        PreviewMouseMove += Move;
        PreviewMouseLeftButtonUp += Up;
        LostMouseCapture += (_, _) => CancelDrag();
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape) CancelDrag();
            if (e.Key == Key.OemComma && Keyboard.Modifiers == ModifierKeys.Control) app.OpenSettings();
        };
        PreviewMouseRightButtonUp += OpenMenu;
        Closed += (_, _) =>
        {
            theme.Changed -= ThemeChanged;
            wake.Stop();
            frames.Stop();
            dragWatch.Stop();
            stackHint.IsOpen = false;
            entranceHit.IsOpen = false;
        };
        Rebuild();
        RestoreExpanded();
    }
    private void EndExternalDrag()
    {
        externalDrag = false;
        Tick();
    }
    private nint Message(nint hwnd, int message, nint wParam, nint lParam, ref bool handled)
    {
        if (message == NativeMethods.WM_ACTIVATEAPP && wParam == 0) app.Presentation.Deactivated();
        if (message == NativeMethods.WM_SETTINGCHANGE)
        {
            theme.Refresh();
            ((App)Application.Current).RefreshAppearance();
            app.RefreshTheme();
        }
        return 0;
    }
    public void InputChanged() => Tick();
    public void RefreshTheme()
    {
        theme.Refresh();
        if (IsLoaded) ApplyMaterial();
    }
    private void ThemeChanged(object? sender, EventArgs e)
    {
        if (IsLoaded) ApplyMaterial();
    }
    private void ApplyMaterial()
    {
        bool dark = theme.EffectiveDark;
        int kind = dark ? 3 : 2;
        if (theme.SolidFallback) kind = 1;
        if (Environment.OSVersion.Version.Build < 22621)
        {
            Background = (Brush)FindResource("ToolbarBackground");
            Shell.Background = Background;
            return;
        }
        int result = NativeMethods.DwmSetWindowAttribute(new WindowInteropHelper(this).Handle, NativeMethods.DWMWA_SYSTEMBACKDROP_TYPE, ref kind, sizeof(int));
        bool material = result >= 0 && kind != 1;
        Background = material ? Brushes.Transparent : (Brush)FindResource("ToolbarBackground");
        Shell.Background = material ? Brushes.Transparent : (Brush)FindResource("ToolbarBackground");
        if (HwndSource.FromHwnd(new WindowInteropHelper(this).Handle) is { } source)
            source.CompositionTarget.BackgroundColor = material ? Colors.Transparent : ((SolidColorBrush)FindResource("ToolbarBackground")).Color;
        System.Windows.Shell.WindowChrome.SetWindowChrome(this, new System.Windows.Shell.WindowChrome
        {
            CaptionHeight = 0, ResizeBorderThickness = new Thickness(0), GlassFrameThickness = material ? new Thickness(-1) : new Thickness(0), CornerRadius = new CornerRadius(32)
        });
        NativeMethods.SetDwmPreference(new WindowInteropHelper(this).Handle, NativeMethods.DWMWA_WINDOW_CORNER_PREFERENCE, NativeMethods.DWMWCP_ROUND);
        if (result < 0) app.Log.Warn("工具条材质不可用，使用纯色底。");
    }
    private bool ReducedMotion => app.Animations.ReducedMotion;
    private ScreenEdge HandleEdge => app.Preferences.Anchor?.Edge ?? app.Preferences.Home.Edge;
    private bool HandleAtEnd => ToolbarRules.HandleAtEnd(app.Preferences.Orientation, HandleEdge);
    private bool Paging => app.Preferences.Pages.Values.DefaultIfEmpty().Max() > 0;
    private readonly ToolbarViewModel model = new();
    private readonly DeskNodes.App.Themes.ThemeService theme;
    private UIElement[] AnimatedParts => Enumerable.Range(0, Parts.Items.Count)
        .Select(i => Parts.ItemContainerGenerator.ContainerFromIndex(i)).OfType<UIElement>().ToArray();
    public void Rebuild()
    {
        if (animating) return;
        Parts.Width = double.NaN;
        Parts.Height = double.NaN;
        model.Round = round;
        model.Update(app, HandleAtEnd, Operate);
        Parts.UpdateLayout();
        if (!round && IsLoaded) Place(ToolbarGeometry.ResolveAnchor(app.Screens.GetScreens(), app.Preferences, app.Preferences.Orientation, Paging));
        UpdateStackHint();
        UpdateEntranceHit();
        if (IsLoaded) Dispatcher.BeginInvoke(() => Tick());
    }
    private void GripLoaded(object sender, RoutedEventArgs e) => grip = (FrameworkElement)sender;
    private void ActionMouseLeave(object sender, MouseEventArgs e) => Hover.Visibility = Visibility.Collapsed;
    private void ActionMouseEnter(object sender, MouseEventArgs e)
    {
        var button = (Button)sender;
        var point = button.TranslatePoint(new Point(), Shell);
        Hover.Width = button.Width;
        Hover.Height = button.Height;
        Hover.Visibility = Visibility.Visible;
        if (ReducedMotion)
        {
            HoverPosition.BeginAnimation(TranslateTransform.XProperty, null);
            HoverPosition.BeginAnimation(TranslateTransform.YProperty, null);
            HoverPosition.X = point.X;
            HoverPosition.Y = point.Y;
        }
        else
        {
            HoverPosition.BeginAnimation(TranslateTransform.XProperty, new DoubleAnimation(point.X, TimeSpan.FromMilliseconds(220)));
            HoverPosition.BeginAnimation(TranslateTransform.YProperty, new DoubleAnimation(point.Y, TimeSpan.FromMilliseconds(220)));
        }
    }
    private void Operate(Action command)
    {
        if (dragging || animating) return;
        app.Run(() =>
        {
            app.Presentation.ExitSelection();
            command();
        });
        Tick(operated: true);
    }
    private RectD visibleBounds;
    private RectD animationBounds;
    private RectD Bounds => visibleBounds;
    public RectD EntranceBounds => Bounds;
    private void Place(RectD rect)
    {
        visibleBounds = rect;
        var frameBounds = animating ? animationBounds : rect;
        Left = frameBounds.X;
        Top = frameBounds.Y;
        Width = frameBounds.Width;
        Height = frameBounds.Height;
        Shell.Width = rect.Width;
        Shell.Height = rect.Height;
        Shell.HorizontalAlignment = HorizontalAlignment.Left;
        Shell.VerticalAlignment = VerticalAlignment.Top;
        Shell.Margin = new Thickness(rect.X - frameBounds.X, rect.Y - frameBounds.Y, 0, 0);
        if (IsLoaded)
        {
            NativeMethods.SetWindowPos(new WindowInteropHelper(this).Handle, 0,
                (int)Math.Round(frameBounds.X * screen.DpiScale), (int)Math.Round(frameBounds.Y * screen.DpiScale),
                (int)Math.Round(frameBounds.Width * screen.DpiScale), (int)Math.Round(frameBounds.Height * screen.DpiScale),
                NativeMethods.NoActivate | NativeMethods.NoZOrder);
            int x = (int)Math.Round((rect.X - frameBounds.X) * screen.DpiScale);
            int y = (int)Math.Round((rect.Y - frameBounds.Y) * screen.DpiScale);
            int widthPixels = (int)Math.Ceiling(rect.Width * screen.DpiScale);
            int heightPixels = (int)Math.Ceiling(rect.Height * screen.DpiScale);
            int diameter = (int)Math.Round(Math.Min(64, Math.Min(rect.Width, rect.Height)) * screen.DpiScale);
            nint region = NativeMethods.CreateRoundRectRgn(x, y, x + widthPixels + 1, y + heightPixels + 1, diameter, diameter);
            // SetWindowRgn transfers ownership only on success.
            if (region != 0 && NativeMethods.SetWindowRgn(new WindowInteropHelper(this).Handle, region, true) == 0)
                NativeMethods.DeleteObject(region);
        }
    }
    public void RestoreExpanded()
    {
        frames.Stop();
        animating = false;
        generation++;
        idle = new();
        var screens = app.Screens.GetScreens();
        screen = ToolbarGeometry.AnchorScreen(screens, app.Preferences);
        round = false;
        Parts.Visibility = Visibility.Visible;
        Parts.Opacity = 1;
        Rebuild();
        foreach (UIElement child in AnimatedParts)
        {
            child.Opacity = 1;
            child.RenderTransform = Transform.Identity;
        }
        RoundLabel.Visibility = Visibility.Collapsed;
        Place(ToolbarGeometry.ResolveAnchor(screens, app.Preferences, app.Preferences.Orientation, Paging));
        Show();
        Place(ToolbarGeometry.ResolveAnchor(screens, app.Preferences, app.Preferences.Orientation, Paging));
        Tick();
    }
    private void UpdateEntranceHit()
    {
        entranceHit.IsOpen = false;
        if (!round || animating || pressed || !IsLoaded) return;
        var home = ToolbarGeometry.ProjectHome(app.Screens.GetScreens(), screen,
            new(Bounds.Center.X * screen.DpiScale, Bounds.Center.Y * screen.DpiScale));
        if (Math.Abs(home.Entrance.X - Left) > 1 || Math.Abs(home.Entrance.Y - Top) > 1) return;
        var area = home.HitZone;
        Entrance.Width = area.Width;
        Entrance.Height = area.Height;
        var outer = new RectangleGeometry(new Rect(0, 0, area.Width, area.Height));
        var circle = new EllipseGeometry(new Rect(Left - area.X, Top - area.Y, 56, 56));
        Entrance.HitGeometry = new CombinedGeometry(GeometryCombineMode.Exclude, outer, circle);
        entranceHit.HorizontalOffset = area.X - Left;
        entranceHit.VerticalOffset = area.Y - Top;
        entranceHit.IsOpen = true;
    }
    private static void PlacePopupBehindActiveApplications(object? sender, EventArgs e)
    {
        if (sender is not System.Windows.Controls.Primitives.Popup popup || popup.Child is not Visual child || PresentationSource.FromVisual(child) is not HwndSource source) return;
        NativeMethods.SetWindowLongPtr(source.Handle, NativeMethods.GWL_EXSTYLE,
            NativeMethods.GetWindowLongPtr(source.Handle, NativeMethods.GWL_EXSTYLE) | NativeMethods.WS_EX_NOACTIVATE | NativeMethods.WS_EX_TOOLWINDOW);
        NativeMethods.SetWindowPos(source.Handle, NativeMethods.NotTopmost, 0, 0, 0, 0,
            NativeMethods.NoMove | NativeMethods.NoSize | NativeMethods.NoActivate);
    }
    private void UpdateStackHint()
    {
        stackHint.IsOpen = false;
        if (round || animating || !app.Preferences.DeskCollapsed || app.NoteCount == 0 || screen is null) return;
        var target = CollapseGeometry.Target(Bounds, screen.WorkArea, 0);
        StackHint.Update(app.Repository.GetNotes().Take(3).Select(note => note.Color.ToString()).ToArray(), app.NoteCount);
        stackHint.HorizontalOffset = target.X - Left;
        stackHint.VerticalOffset = target.Y - Top;
        stackHint.IsOpen = true;
    }
    private void EntranceEnter(object sender, MouseEventArgs e) => Tick();
    private void EntranceDragEnter(object sender, DragEventArgs e)
    {
        externalDrag = true;
        Tick();
    }
    private void EntranceDragEnd(object sender, DragEventArgs e) => EndExternalDrag();
    private void StackHintClick(object sender, MouseButtonEventArgs e) => Operate(app.ToggleCollapsed);
    private void OpenMenu(object sender, MouseButtonEventArgs e)
    {
        if (OnButton(e.OriginalSource as DependencyObject)) return;
        var menu = app.Menus.ToolbarMenu();
        menu.Opened += (_, _) =>
        {
            menuOpen = true;
            Tick();
        };
        menu.Closed += (_, _) =>
        {
            menuOpen = false;
            Tick();
        };
        menu.PlacementTarget = this;
        menu.IsOpen = true;
        e.Handled = true;
    }
}
