import { createMemo, createResource, createSignal, For, onCleanup, onMount, Show } from "solid-js";
import { invoke } from "@tauri-apps/api/core";
import appIcon from "./assets/app-icon.png";
import "./App.css";

type ConfigEntryKind = "boolean" | "number" | "text";

type ConfigEntry = {
  key: string;
  value: string;
  kind: ConfigEntryKind;
  description: string;
};

type ConfigFile = {
  id: string;
  title: string;
  path: string;
  writable: boolean;
  entries: ConfigEntry[];
};

type RuntimeStatus = {
  matrix: Record<string, string>;
  sysstates: string;
  keyboard_backlight: {
    built_in_percent: number | null;
    detachable_level: number | null;
    detachable_max: number;
  };
};

type DisplayBrightnessScreen = {
  id: "main" | "lower";
  name: string;
  path: string;
  available: boolean;
  percent: number | null;
};

type DisplayBrightness = {
  main: DisplayBrightnessScreen;
  lower: DisplayBrightnessScreen;
};

type HelperAction = {
  id: string;
  label: string;
  helper: "matrix" | "sysstates" | "fnkeys";
  args: string[];
};

const actions: HelperAction[] = [
  { id: "matrix-reconcile", label: "Reconcile matrix", helper: "matrix", args: ["reconcile"] },
  { id: "display-auto", label: "Display auto", helper: "sysstates", args: ["display", "auto"] },
  { id: "display-attached", label: "Attached layout", helper: "sysstates", args: ["display", "attached"] },
  { id: "display-detached", label: "Detached layout", helper: "sysstates", args: ["display", "detached"] },
  { id: "system-light", label: "Built-in keyboard light", helper: "sysstates", args: ["light"] },
  { id: "lights-off", label: "All keyboard lights off", helper: "sysstates", args: ["light-off"] },
  { id: "power", label: "Apply power profile", helper: "sysstates", args: ["power"] },
  { id: "kbb-0", label: "Detachable light off", helper: "fnkeys", args: ["kbb", "0"] },
  { id: "kbb-1", label: "Detachable light low", helper: "fnkeys", args: ["kbb", "1"] },
  { id: "kbb-2", label: "Detachable light mid", helper: "fnkeys", args: ["kbb", "2"] },
  { id: "kbb-3", label: "Detachable light high", helper: "fnkeys", args: ["kbb", "3"] },
  { id: "notify-test", label: "Notification test", helper: "fnkeys", args: ["notify-test"] },
];

const loadConfigs = () => invoke<ConfigFile[]>("read_configs");
const loadStatus = () => invoke<RuntimeStatus>("runtime_status");
const loadDisplayBrightness = () => invoke<DisplayBrightness>("display_brightness");

function App() {
  const [configs, { refetch: refetchConfigs, mutate }] = createResource(loadConfigs);
  const [status, { refetch: refetchStatus }] = createResource(loadStatus);
  const [brightness, { refetch: refetchBrightness, mutate: setBrightness }] =
    createResource(loadDisplayBrightness);
  const [selectedFile, setSelectedFile] = createSignal("sysstates");
  const [filter, setFilter] = createSignal("");
  const [notice, setNotice] = createSignal("");
  const [busyAction, setBusyAction] = createSignal("");
  const [pendingBrightness, setPendingBrightness] = createSignal("");
  const [settingsOpen, setSettingsOpen] = createSignal(false);
  const configTimers = new Map<string, number>();

  const activeConfig = createMemo(() => {
    const list = configs() ?? [];
    return list.find((config) => config.id === selectedFile()) ?? list[0];
  });

  const visibleEntries = createMemo(() => {
    const query = filter().trim().toLowerCase();
    const entries = activeConfig()?.entries ?? [];
    if (!query) return entries;
    return entries.filter((entry) =>
      `${entry.key} ${entry.description} ${entry.value}`.toLowerCase().includes(query),
    );
  });

  const updateEntry = (fileId: string, key: string, value: string) => {
    mutate((current) =>
      current?.map((file) =>
        file.id !== fileId
          ? file
          : {
              ...file,
              entries: file.entries.map((entry) =>
                entry.key === key ? { ...entry, value } : entry,
              ),
            },
      ),
    );
  };

  const saveConfig = async (fileId: string) => {
    const config = configs()?.find((candidate) => candidate.id === fileId);
    if (!config) return;
    setBusyAction(`config-${fileId}`);
    setNotice(`Applying ${config.title}...`);
    try {
      await invoke("write_config", {
        fileId: config.id,
        entries: config.entries.map(({ key, value }) => ({ key, value })),
      });
      setNotice(`Applied ${config.title}`);
      await refetchConfigs();
    } catch (error) {
      setNotice(`Apply failed: ${error}`);
    } finally {
      setBusyAction("");
    }
  };

  const scheduleConfigApply = (fileId: string, immediate = false) => {
    const existingTimer = configTimers.get(fileId);
    if (existingTimer !== undefined) {
      window.clearTimeout(existingTimer);
      configTimers.delete(fileId);
    }

    if (immediate) {
      void saveConfig(fileId);
      return;
    }

    const timer = window.setTimeout(() => {
      configTimers.delete(fileId);
      void saveConfig(fileId);
    }, 700);
    configTimers.set(fileId, timer);
    setNotice("Change queued...");
  };

  const changeEntry = (
    fileId: string,
    key: string,
    value: string,
    immediate = false,
  ) => {
    updateEntry(fileId, key, value);
    scheduleConfigApply(fileId, immediate);
  };

  const runAction = async (action: HelperAction) => {
    setBusyAction(action.id);
    setNotice(`Running ${action.label}...`);
    try {
      const result = await invoke<string>("run_helper", {
        helper: action.helper,
        args: action.args,
      });
      setNotice(result || `${action.label} completed`);
      await refetchStatus();
    } catch (error) {
      setNotice(`${action.label} failed: ${error}`);
    } finally {
      setBusyAction("");
    }
  };

  const physicalMode = createMemo(() => status()?.matrix.physical_mode ?? "unknown");
  const isAttached = createMemo(() => physicalMode() === "attached");
  const builtInBacklight = createMemo(() => {
    const value = status()?.keyboard_backlight?.built_in_percent;
    return value === null || value === undefined ? "n/a" : `${value}%`;
  });
  const detachableBacklight = createMemo(() => {
    const backlight = status()?.keyboard_backlight;
    if (!backlight || backlight.detachable_level === null) return "n/a";
    return `${backlight.detachable_level}/${backlight.detachable_max}`;
  });

  const refreshLiveState = async () => {
    await Promise.all([refetchStatus(), refetchBrightness()]);
  };

  onMount(() => {
    const liveTimer = window.setInterval(() => {
      void refreshLiveState();
    }, 2500);

    const configTimer = window.setInterval(() => {
      const activeElement = document.activeElement;
      const editingSettings =
        activeElement instanceof Element && activeElement.closest(".settings-grid");
      if (!editingSettings && configTimers.size === 0) {
        void refetchConfigs();
      }
    }, 15000);

    onCleanup(() => {
      window.clearInterval(liveTimer);
      window.clearInterval(configTimer);
      for (const timer of configTimers.values()) {
        window.clearTimeout(timer);
      }
      configTimers.clear();
    });
  });

  const setDisplayBrightness = async (
    target: "main" | "lower",
    percent: number,
    label: string,
  ) => {
    const bounded = Math.max(0, Math.min(100, Math.round(percent)));
    setPendingBrightness(`${target}-${bounded}`);
    setNotice(`Setting ${label} to ${bounded}%...`);
    try {
      const next = await invoke<DisplayBrightness>("set_display_brightness", {
        target,
        percent: bounded,
      });
      setBrightness(next);
      setNotice(`${label}: ${bounded}%`);
    } catch (error) {
      setNotice(`Brightness update failed: ${error}`);
      await refetchBrightness();
    } finally {
      setPendingBrightness("");
    }
  };

  return (
    <main class="shell">
      <header class="topbar">
        <div class="brand">
          <img src={appIcon} alt="" aria-hidden="true" />
          <div>
            <h1>Zenbook Duo Tray Utility</h1>
            <p>Live controls and helper configuration.</p>
          </div>
        </div>
        <div class="topbar-actions">
          <button onClick={() => setSettingsOpen((open) => !open)}>
            {settingsOpen() ? "Hide Settings" : "Settings"}
          </button>
          <button class="primary" onClick={() => void refreshLiveState()}>
            Refresh
          </button>
        </div>
      </header>

      <section class="tray-panel">
        <div class="mode-card" classList={{ active: isAttached() }}>
          <span class="mode-symbol attached-symbol" aria-hidden="true"></span>
          <div>
            <strong>Attached</strong>
            <small>{isAttached() ? "active" : "inactive"}</small>
          </div>
        </div>
        <div class="mode-card" classList={{ active: !isAttached() }}>
          <span class="mode-symbol detached-symbol" aria-hidden="true"></span>
          <div>
            <strong>Detached</strong>
            <small>{!isAttached() ? "active" : "inactive"}</small>
          </div>
        </div>
        <DisplayControl
          screen={brightness()?.main}
          busy={busyAction() === "brightness-main" || pendingBrightness().startsWith("main-")}
          onSet={(percent) => void setDisplayBrightness("main", percent, "eDP-1")}
        />
        <DisplayControl
          screen={brightness()?.lower}
          busy={busyAction() === "brightness-lower" || pendingBrightness().startsWith("lower-")}
          onSet={(percent) => void setDisplayBrightness("lower", percent, "eDP-2")}
        />
      </section>

      <section class="status-band">
        <div class="status-item">
          <span>Physical</span>
          <strong>{status()?.matrix.physical_mode ?? "unknown"}</strong>
        </div>
        <div class="status-item">
          <span>Transport</span>
          <strong>{status()?.matrix.transport ?? "unknown"}</strong>
        </div>
        <div class="status-item">
          <span>USB</span>
          <strong>{status()?.matrix.usb_present ?? "unknown"}</strong>
        </div>
        <div class="status-item">
          <span>Bluetooth</span>
          <strong>{status()?.matrix.bt_connected ?? "unknown"}</strong>
        </div>
        <div class="status-item">
          <span>Built-in light</span>
          <strong>{builtInBacklight()}</strong>
        </div>
        <div class="status-item">
          <span>Detachable light</span>
          <strong>{detachableBacklight()}</strong>
        </div>
      </section>

      <section class="workspace" classList={{ expanded: settingsOpen() }}>
        <aside class="actions">
          <h2>Quick Actions</h2>
          <div class="action-list">
            <For each={actions}>
              {(action) => (
                <button
                  class="action-button"
                  disabled={busyAction() === action.id}
                  onClick={() => void runAction(action)}
                >
                  <span>{action.label}</span>
                  <small>{action.helper}</small>
                </button>
              )}
            </For>
          </div>
        </aside>

        <Show when={settingsOpen()}>
        <section class="config-panel">
          <div class="config-head">
            <div class="tabs">
              <For each={configs() ?? []}>
                {(config) => (
                  <button
                    classList={{ active: selectedFile() === config.id }}
                    onClick={() => setSelectedFile(config.id)}
                  >
                    {config.title}
                  </button>
                )}
              </For>
            </div>
            <div class="config-tools">
              <input
                value={filter()}
                onInput={(event) => setFilter(event.currentTarget.value)}
                placeholder="Filter settings"
              />
              <button
                class="primary"
                disabled={busyAction().startsWith("config-")}
                onClick={() => activeConfig() && void saveConfig(activeConfig()!.id)}
              >
                Apply now
              </button>
            </div>
          </div>

          <Show when={activeConfig()}>
            {(config) => (
              <>
                <div class="path-row">
                  <span>{config().path}</span>
                  <strong>{config().writable ? "writable" : "sudo may be required"}</strong>
                </div>
                <div class="settings-grid">
                  <For each={visibleEntries()}>
                    {(entry) => (
                      <label class="setting-row">
                        <span>
                          <strong>{entry.key}</strong>
                          <small>{entry.description}</small>
                        </span>
                        <Show
                          when={entry.kind === "boolean"}
                          fallback={
                            <input
                              value={entry.value}
                              inputMode={entry.kind === "number" ? "numeric" : "text"}
                              onInput={(event) =>
                                changeEntry(config().id, entry.key, event.currentTarget.value)
                              }
                            />
                          }
                        >
                          <select
                            value={entry.value}
                            onChange={(event) =>
                              changeEntry(config().id, entry.key, event.currentTarget.value, true)
                            }
                          >
                            <option value="true">true</option>
                            <option value="false">false</option>
                          </select>
                        </Show>
                      </label>
                    )}
                  </For>
                </div>
              </>
            )}
          </Show>
        </section>
        </Show>
      </section>

      <Show when={notice()}>
        <footer class="notice">{notice()}</footer>
      </Show>
    </main>
  );
}

function DisplayControl(props: {
  screen?: DisplayBrightnessScreen;
  busy: boolean;
  onSet: (percent: number) => void;
}) {
  const percent = () => props.screen?.percent ?? null;
  const available = () => props.screen?.available ?? false;
  const stepSize = 10;

  return (
    <div class="display-control">
      <div class="display-head">
        <span>{props.screen?.name ?? "Display"}</span>
        <strong>{percent() === null ? "n/a" : `${percent()}%`}</strong>
      </div>
      <div class="display-meter" aria-hidden="true">
        <span style={{ width: `${percent() ?? 0}%` }}></span>
      </div>
      <label class="brightness-row">
        <span>Brightness</span>
        <input
          type="range"
          min="0"
          max="100"
          step="1"
          value={percent() ?? 0}
          disabled={!available() || props.busy}
          onChange={(event) => props.onSet(Number(event.currentTarget.value))}
        />
      </label>
      <div class="step-row">
        <button
          class="step-button"
          disabled={!available() || props.busy}
          onClick={() => props.onSet(Math.max(0, (percent() ?? 0) - stepSize))}
        >
          -{stepSize}%
        </button>
        <button
          class="step-button"
          disabled={!available() || props.busy}
          onClick={() => props.onSet(Math.min(100, (percent() ?? 0) + stepSize))}
        >
          +{stepSize}%
        </button>
      </div>
    </div>
  );
}

export default App;
