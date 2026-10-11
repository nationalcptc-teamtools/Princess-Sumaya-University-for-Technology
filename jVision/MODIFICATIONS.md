# jVision — modifications log

Everything below was added on top of the pre-existing jVision. Nothing removes
existing functionality — new tabs live next to the old ones, the topology
renderer is backwards compatible (still takes just `List<Box>` if no pivots
are passed), and no existing endpoint changed shape (except `Box` DTOs, which
gained an optional `Stage` field).

- **Data model & migration**
- **Created Accounts tab** (auto-mirrors into Credentials)
- **Progress board** per-box (with a dedicated `/board` view)
- **Attack path** (labeled arrows overlaid on the topology)
- **Password tracker** (usages per credential, integrated into the Credentials page)
- **Box presence** (see who else is on the same box)
- **Instant search palette** (Ctrl-K)
- **Topology centering fix + caption removed**
- **Topology download from the Attack Path page**

---

## 0. Rebuild after pulling

The changes include one hand-written EF migration (`Server/Migrations/20260901220000_multi-feature-baseline.cs`) that gets auto-applied on startup (`Program.cs` calls `db.Database.Migrate()`).

```
sudo docker compose up --build
```

If the container was already running, `Ctrl+C` first so the rebuild picks up the source changes.

---

## 1. Data model & migration

Added tables/columns (all in one migration):

- `Boxes.Stage` — nullable string. Values: `todo` / `enum` / `foothold` / `privesc` / `owned`. Null is treated as `todo`.
- `CreatedAccount` — mid-engagement account rows.
- `PivotEdge` — attack-path arrows.
- `CredUsage` — per-credential "tried it here" log.

`Cred.Origin` gained one more allowed value: `Created` (green badge). It's the origin used when a Created Account auto-mirrors into the Credentials list.

Files touched:
- `Server/Models/Box.cs`, `Shared/Models/BoxDTO.cs` — added `Stage`.
- `Shared/Models/CreatedAccount.cs`, `PivotEdge.cs`, `CredUsage.cs` — new.
- `Server/Data/JvisionServerDBContext.cs` — new `DbSet`s + indexes.
- `Server/Migrations/20260901220000_multi-feature-baseline.cs` + `.Designer.cs`.
- `Server/Migrations/JvisionServerDBContextModelSnapshot.cs` — updated.
- `Server/Controllers/CredsController.cs` — allow `"Created"` origin.

---

## 2. Created Accounts tab

For accounts you create during the engagement (SSH users, AD accounts, CMS admins, …).

### Where
Sidebar → **Created Accounts** (`/created-accounts`).

### How to use
1. Fill in the small form at the top:
   - `target IP` — the host the account lives on (freeform; can be a host you haven't scanned yet).
   - `service` — freeform tag: `SSH`, `AD`, `WordPress admin`, `MSSQL`, …
   - `username`, `password` — required (username); password optional.
   - `privilege` — freeform: `local user`, `admin`, `domain admin`.
   - `notes` — how / why you created it.
2. Click **Add**.
3. The row appears in the table below **and** in the Credentials page as a new
   Cred with a green `Created` badge — one place to see every credential you
   know about.
4. Deleting a Created Account also deletes its mirrored Cred (no orphans).

### Endpoints
- `GET /CreatedAccounts` → list
- `POST /CreatedAccounts` → add (auto-mirrors into `Cred`)
- `PUT /CreatedAccounts/{id}` → edit
- `DELETE /CreatedAccounts/{id}` → remove (also deletes mirrored `Cred`)

### Files
- `Server/Controllers/CreatedAccountsController.cs`
- `Client/Pages/CreatedAccounts.razor`

---

## 3. Progress board

Every box has a stage. See the whole team's progress at a glance.

### Where
- **Home page** (`/`) — each box row shows a colored dropdown chip you can change inline.
- **Board** (`/board`) — five columns (`To-scan`, `Enumerating`, `Foothold`, `Priv-esc`, `Owned`), boxes grouped by stage, with counts.

### How to use
- On Home: click the stage chip on any row → pick a new stage.
- On `/board`: same dropdown on the card view.
- Changes broadcast to all connected browsers immediately.

### Endpoint
- `POST /Box/{id}/stage` with `{"Stage":"foothold"}` — lightweight endpoint so you don't have to round-trip the whole `BoxDTO` (including services) just to flip one label. The full `PUT /Box` also honours the field.
- `GET /Box` — DTOs now include `stage`.

### Files
- `Server/Controllers/BoxController.cs` — new `PostStage` endpoint + `Stage` in POST/PUT/GET mappings.
- `Client/Pages/Board.razor` — new page.
- `Client/Pages/Index.razor` — inline chip + dropdown on collapsed/expanded headers.

---

## 4. Attack path (pivot edges on topology)

Record every lateral move; each edge becomes a labeled colored arrow on the topology diagram. The topology *becomes* the story of the engagement.

### Where
Sidebar → **Attack Path** (`/pivots`).

### How to use
1. Pick **source IP** and **target IP** from the dropdowns (populated from all known boxes).
2. Pick a **technique**: `creds`, `exploit`, `rce`, `session`, `relay`, `phish`, `other`.
3. Free-text **label** — e.g. `admin:Password1!`, `CVE-2023-1234`, `pass-the-ticket`.
4. Click **Add**.
5. Open the topology (buttons on this page — see §10 — or on Home): the arrow shows up immediately, colored by technique.

### Techniques → colors on the topology
- `creds` → magenta
- `exploit` → red
- `rce` → orange
- `session` → teal
- `relay` → violet
- `phish` → amber
- `other` → slate

### Endpoints
- `GET /PivotEdges` → list
- `POST /PivotEdges` → add
- `DELETE /PivotEdges/{id}` → remove

### Files
- `Server/Controllers/PivotEdgesController.cs`
- `Client/Pages/Pivots.razor`
- `Server/Download/TopologyRenderer.cs` — new `PivotEdgesOverlay` + per-technique arrowhead markers.
- `Server/Controllers/DownloadController.cs` — passes pivot edges into the renderer.

---

## 5. Password tracker (integrated into the Credentials page)

Every credential can now record *where* it was tried and whether it worked.

### Where
**Credentials** page (`/credentials`) — click the target icon on any credential row.

### How to use
1. Click the **target** icon on the right of any cred to expand its usage panel.
2. The panel lists every host/service where this cred has been tried, with status
   (`valid` / `invalid` / `untested`).
3. To log a new usage: pick a host from the dropdown (populated from known
   boxes), fill in service / port / status / notes, click **Log**.
4. The cred row now shows compact chips like `✓2 ✗1` so you can scan
   the columns and see which creds are hot.

### Endpoints
- `GET /CredUsages?credId=X` → all usages for a cred
- `POST /CredUsages` → add
- `PUT /CredUsages/{id}` → edit
- `DELETE /CredUsages/{id}` → remove
- `GET /CredUsages/suggestions/{credId}?service=SMB` → hosts running that service that haven't been tried yet

### Files
- `Server/Controllers/CredUsagesController.cs`
- `Client/Pages/Credies.razor` — added inline usages panel per cred row.

---

## 6. Box presence

See who else is looking at a box in real time (SignalR).

### Where
**Home** page (`/`) — expand any box row. If a teammate expands the same row,
you'll see their initials as a colored badge on the header (yours is filtered
out to avoid noise).

### How it works
- Expanding a row calls `hub.SendAsync("JoinBox", boxId, userName)`.
- Collapsing / navigating away calls `LeaveBox`.
- Disconnecting drops you from every presence group automatically.
- Server broadcasts `BoxPresenceChanged(boxId, users[])` to everyone.

### Files
- `Server/Hubs/BoxHub.cs` — new `JoinBox` / `LeaveBox` hub methods, presence tracking, `BoxPresenceChanged` event.
- `Client/Pages/Index.razor` — `PresenceChip` render fragment + `OnCollapseChanged` handler.

---

## 7. Instant search (Ctrl-K)

Global search palette. Works on any page.

### How to use
- Press **Ctrl+K** (or **Cmd+K** on Mac) anywhere in the app.
- Type — results filter live across:
  - **Hosts** (IP, hostname, OS, subnet, comments, stage, services / ports)
  - **Credentials** (text, source, origin)
  - **Created accounts** (username, password, service, notes)
  - **Pivot edges** (source, target, technique, label)
- **↑ / ↓** to navigate results, **Enter** to open, **Esc** to close. Matching terms are highlighted in yellow.

### Caching
Data is fetched on open and cached for 30s. Reopen the palette after making
changes if you don't see fresh results (or just wait 30s).

### Files
- `Client/Shared/SearchPalette.razor` — component (mounted globally in `MainLayout.razor`).
- `Client/wwwroot/javascript/jvision-search.js` — global Ctrl-K keyboard hook.
- `Client/wwwroot/index.html` — `<script>` include.

---

## 8. Topology centering fix

Bug fix: previously the topology had a fixed 3-column subnet grid, so a single subnet was left-aligned to the leftmost column rather than sitting under the router.

### Now
- 1 subnet → centered under the router.
- 2 subnets → centered as a pair.
- 3 subnets → same as before (full 3-column row).
- More than 3 → first rows fill 3 columns; the trailing partial row is centered too (e.g. 5 subnets → 3 on top row, 2 centered below).

### Files
- `Server/Download/TopologyRenderer.cs` — `Compute()` now uses `effectiveCols = min(SubCols, groupCount)` and centers each row independently.

---

## 9. Removed "jVision Network Topology" footer caption

The italic timestamp caption at the bottom of the topology PNG/SVG was
dropped, and the reserved 60px trailing whitespace was trimmed to 20px.

### Files
- `Server/Download/TopologyRenderer.cs` — removed the trailing `<text>` and shrank `CanvasH`.

---

## 10. Topology download — with or without arrows (Home + Attack Path)

Both **Home** and **Attack Path** now expose the same two download groups plus
the drawio link:

**With arrows** (attack story — use for the "how we owned it" section of the report)
- **With arrows (SVG)** → `/download/topology.svg`
- **PNG** → rasterises that SVG client-side to `topology-YYYY-MM-DD-HHMM.png`

**Plain** (network map only — use for the "environment" section of the report)
- **Plain (SVG)** → `/download/topology.svg?pivots=false` (file name becomes `topology-plain.svg`)
- **PNG** → rasterises the plain SVG to `topology-plain-YYYY-MM-DD-HHMM.png`

**drawio** → `/download/topology.drawio` (editable in app.diagrams.net; no arrows,
since drawio has no native concept of the overlay).

### Server contract
`GET /download/topology.svg?pivots=true` (default) or `?pivots=false`.

### Files
- `Server/Controllers/DownloadController.cs` — `pivots` query param.
- `Client/Pages/Pivots.razor` — two button groups + `DownloadTopologyPng(bool pivots)`.
- `Client/Pages/Index.razor` — matching two button groups + updated `DownloadTopologyPng(bool pivots)`.

---

## Nav bar order

```
Home
Credentials
Created Accounts   ← new
Board              ← new
Attack Path        ← new
Logs
Scans
Team IPs
Scratchpad
… (custom tabs)
New tab
```

## Full file inventory

**New**
- `Shared/Models/CreatedAccount.cs`
- `Shared/Models/PivotEdge.cs`
- `Shared/Models/CredUsage.cs`
- `Server/Controllers/CreatedAccountsController.cs`
- `Server/Controllers/PivotEdgesController.cs`
- `Server/Controllers/CredUsagesController.cs`
- `Server/Migrations/20260901220000_multi-feature-baseline.cs` (+ Designer)
- `Client/Pages/CreatedAccounts.razor`
- `Client/Pages/Board.razor`
- `Client/Pages/Pivots.razor`
- `Client/Shared/SearchPalette.razor`
- `Client/wwwroot/javascript/jvision-search.js`

**Modified**
- `Server/Models/Box.cs`
- `Shared/Models/BoxDTO.cs`
- `Server/Data/JvisionServerDBContext.cs`
- `Server/Migrations/JvisionServerDBContextModelSnapshot.cs`
- `Server/Hubs/BoxHub.cs`
- `Server/Controllers/BoxController.cs`
- `Server/Controllers/CredsController.cs`
- `Server/Controllers/DownloadController.cs`
- `Server/Download/TopologyRenderer.cs`
- `Client/Shared/NavMenu.razor`
- `Client/Shared/MainLayout.razor`
- `Client/Pages/Index.razor`
- `Client/Pages/Credies.razor`
- `Client/wwwroot/index.html`
