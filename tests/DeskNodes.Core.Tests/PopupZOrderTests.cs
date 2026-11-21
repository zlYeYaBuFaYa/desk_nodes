using DeskNodes.Core.Presentation;

namespace DeskNodes.Core.Tests;

public sealed class PopupZOrderTests
{
    [Fact]
    public void EdgePopupSitsJustAboveItsOwnerAndBelowOtherWindows()
    {
        var note = new ZBandWindow(1, true);
        var app = new ZBandWindow(2, false);
        var nearer = new ZBandWindow(5, false);
        var popup = new ZBandWindow(3, false);
        var toolbar = new ZBandWindow(4, false);
        Assert.Equal(2, PopupZOrder.InsertAfter([note, popup, app, toolbar], popup.Id, toolbar.Id));
        Assert.Equal(5, PopupZOrder.InsertAfter([app, nearer, toolbar], popup.Id, toolbar.Id));
        Assert.Null(PopupZOrder.InsertAfter([note, popup, toolbar], popup.Id, toolbar.Id));
        Assert.Null(PopupZOrder.InsertAfter([popup, toolbar], popup.Id, toolbar.Id));
        Assert.Equal(2, PopupZOrder.InsertAfter([app, toolbar], popup.Id, toolbar.Id));
        Assert.Null(PopupZOrder.InsertAfter([toolbar], popup.Id, 9));
    }
}
