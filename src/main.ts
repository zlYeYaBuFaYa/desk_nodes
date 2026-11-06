import { mount } from "svelte";
import App from "./App.svelte";
import Management from "./Management.svelte";
import "./styles/tokens.css";
import "./styles/app.css";
mount(new URLSearchParams(location.search).has("panel") ? Management : App, { target: document.getElementById("app")! });
