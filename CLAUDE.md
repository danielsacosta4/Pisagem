# Pisagem

Pisagem ("pisar" + "paisagem": step into the landscape) generates random loop routes for walking, hiking, road cycling and mountain biking. Portugal-first: Portuguese safety data, PR/GR trails, Portuguese + English. Domain to register: pisagem.com.

The goal is to be the best route generator for Portugal. The closest competitor is Trail Router (trailrouter.com): free, very good, same feature set. Pisagem wins on route quality and Portuguese data, not on features alone.

## Where things stand

The working prototype is one file, `pisagem.html` (copy it into this repo as the starting point). It runs entirely in the browser:

- Map: Leaflet 1.9.4 (cdnjs), CARTO Voyager / Dark tiles, OpenTopoMap.
- Routing: public OpenRouteService API with the user's own key (kept in localStorage). Round trips (`options.round_trip`) or loops through waypoints, with elevation and `extra_info` waytype, waycategory, green.
- Map data: public Overpass API for scenery, PR/GR/PL hiking relations, and roads near each route (sidewalk, lit, roundabout tags).

### Features and the rules behind them

| Feature | Rule in the prototype |
| --- | --- |
| Activities | walk = foot-walking, hike = foot-hiking, road bike = cycling-regular, MTB = cycling-mountain |
| Distance | 2–60 km slider |
| Terrain | Flat: 0–10 m climb/km, no 200 m stretch steeper than 6%. Some hills: 8–25 m/km, max 14%. Hilly: over 20 m/km |
| Candidates | 4 per round, up to 3 rounds; stop once one fits everything or 2 are acceptable; show best 5 |
| Scenic | half the candidates route through scenic anchors (viewpoints, peaks, water, parks, woods); route scored on share within 200 m of scenery; target 35% |
| Official trails (hike) | PR/GR/PL relations from OSM; waypoints placed on them; target 50% of route within 40 m |
| Avoid busy roads | at most 5% on ORS waytype 1–2 |
| Always rejected | dead ends (goes 30 m in and back out); U-turn detours on roads (100/200 m windows, legs closer than 0.7 × depth, unless the climb is over 8%); any motorway; more than 100 m in one run on trunk/primary |
| Walk/hike only | rejected if more than 200 m in one run on a road tagged sidewalk=no, or more than 40 m around a roundabout |
| After dark | rejected if more than 150 m unlit in one run (lit=no, or untagged path/track/bridleway); no waypoints in woods, parks, peaks or on PR/GR trails |
| Route editing | drag numbered points, drag or click the line to add a point, right-click/long-press to remove, drag start to replan, Undo; edited routes are never rejected, only warned |
| Road-type mix | bar showing share of each ORS waytype |
| Place my points | "Desenhar" tab: tap start, then each point (a dark hint says what to tap next); Volta ao início / Só ida; Desfazer, Limpar; same editing tools |
| Place search | Photon (photon.komoot.io), biased to the map centre |
| My workouts | Import in the "O meu mapa" tab: Apple's whole export.zip/exportar.zip (read entry by entry, zip64-safe; export.xml streamed for heart-rate samples and Workout statistics, matched to routes by FileReference), or export.xml plus its GPX files, or any GPX (heart rate, cadence, power, temperature from extensions). Stored per workout: sport, real duration, avg/max/min heart rate, active calories, cadence, power, temperature, and heart rate per point (shown as a red line on the elevation chart). Re-importing richer data upgrades a workout instead of skipping it. Stored in IndexedDB (migrated from localStorage); drawn on the map; open one as a ticket in Desenhar with real time; "Caminhos novos" (in Mais opções once workouts exist) penalises routes on paths already done (40 m grid, share sampled every 50 m) |
| O meu mapa · My map | its own tab showing all imported workouts: heat (stacked translucent lines on a canvas), lines or start points; year filter; totals incl. "different paths" km (20 m steps, a step counts if its 40 m cell wasn't covered by an earlier workout); tap a line to open that workout |
| Share links | route kept after `#` in the address: activity, start, points, loop, options; opening it rebuilds the route in the Desenhar tab |
| Map layers | Mapa (CARTO light/dark with a key, else Esri Light/Dark Gray Canvas), Satélite (Esri imagery + Esri roads and labels), Topográfico (OpenTopoMap), Ciclismo (CyclOSM), Detalhado (CARTO Voyager with a key, else Esri World Street Map); on satellite the route is bright mint on a near-black outline; overlays: Waymarked Trails hiking and cycling, Esri hillshade |
| Design | "Bilhete": each route is a ticket (dot-matrix Doto numbers, Overpass text). One language at a time, PT/EN switch in the header (default from the browser, saved) |
| Layout | Map first, full screen. Header: wordmark + tabs Gerar / Desenhar / O meu mapa, place search, Camadas, PT·EN, settings (theme + routing key). One floating card at a time on the left: plan card (start, 4 activity icons, distance with −/+ and a time estimate, "Mais opções" row showing chosen options as tags, Gerar percurso) → Mais opções (terrain, switches with one-line explanations; PR/GR only for hikes) → result ticket at the bottom with route options as tabs; the plan then shrinks to a summary pill with "Alterar". Phones (≤720 px): tabs become a bottom bar, cards become bottom sheets, the ticket sheet folds down with its handle. Routes are fitted into the part of the map the cards leave free |
| Shade and fire risk | "Sombra" switch: prefers woods, parks and water (ORS green factor 1, shade anchors weighted ×2.5, scored on share inside woods/parks or within 50 m of water, target 30%). Plan card shows today's max temperature (Open-Meteo) and IPMA fire risk (rcm-d0.json, nearest municipality within 30 km); at ≥28 °C it offers "Ligar Sombra". On IPMA level 4–5: no woods/peak/trail waypoints, PR/GR anchors off, routes over 20% inside woods rejected, reason on the ticket. Woods are tested as areas (point in polygon, incl. multipolygon relations), not just edges. Declared fire alerts (forest access bans) are not yet read: no open API found |
| Stops | Overpass nodes within 60 m of the line: drinking water, cafés/bars/restaurants, toilets, viewpoints, trailheads; icons on the map (cafés capped at 12), counts on the ticket |
| Surface | ORS extra_info surface grouped: asphalt/concrete, calçada/empedrado (paving stones), dirt/gravel, no data; bar on the ticket; road bike penalised for unpaved (issue over 5%) and cobbles |
| Workouts | Open read-only in O meu mapa (taps do nothing); "Editar" moves one to Desenhar; "Um novo parecido" plans a loop from the same start with the same activity, distance and terrain, Caminhos novos on. Points keep heart rate and seconds since start |
| Line colour | Simples / Inclinação (diverging, ±3/±8%) / Pulsação (zones Z1–Z5 at 60/70/80/90% of max HR) / Velocidade (quintiles of the workout); legend under the chart. Chart: elevation, plus a separate heart-rate panel (no dual axis); hover or drag reads km, height, gradient, heart rate, speed and marks the map |
| O meu mapa totals | calories; kilometres per month (last 12 months or the chosen year); time in heart-rate zones (gaps over 60 s are pauses); records per sport (longest, fastest, most climb), each opens its workout. Max heart rate set in settings, else the highest seen |
| Other | Dia/Noite/Auto theme (in settings), elevation chart with map hover, GPX export, client-side limit of 30 routing requests per minute |

### Lessons from the owner's testing

- Walks circled roundabouts and made out-and-back detours on roads. Fixed with the post-filters above, but filtering after the fact wastes requests. Phase 1 should build these rules into the routing profile instead.
- "Couldn't reach the routing service" was really the free key's rate limit: ORS refusals can't be read from a file:// page, so they looked like network errors.
- Sidewalk and lighting tags are often missing in Portugal. Treat untagged as unknown, not as bad.
- OpenStreetMap's own tile servers block file:// pages (no Referer). Don't use them; serve our own tiles once hosted.
- Since August 2026 CARTO basemaps need a free key (carto.com/basemaps/apikey, `?key=` on each tile URL); without it tiles carry an "API KEY REQUIRED" watermark. The prototype takes an optional CARTO key in settings and falls back to Esri.
- Apple's workout-routes GPX files hold only the track; heart rate and calories are only in export.xml, so import the whole export zip.
- Theme colours don't work on satellite imagery: the route needs its own high-contrast style there.
- The layout was rebuilt (map first, three tabs, one card at a time) because the single long column with bilingual labels wasn't intuitive.
- Always generate and check real routes before handing a change to the owner. The prototype was only tested against simulated routes, and real-world bugs slipped through.

## Phase 1: our own routing server (current goal)

### Server

Owner's Proxmox host: 12 cores, more than 1 TB HDD, about 8 GB free RAM.

- Decided: a Debian LXC (not a VM), with nesting and keyctl on for Docker, 4 cores, 6 GB RAM (leave 2 GB for the host), swap, about 60 GB disk. OpenRouteService can also run as a plain Java program if Docker in LXC causes trouble.
- Later: cloudflared and the Pisagem backend each in their own small LXC.
- OpenRouteService (official Docker image) with the Geofabrik Portugal extract (portugal-latest.osm.pbf, about 405 MB, refreshed daily) and elevation on.
- Start with foot-walking and foot-hiking only. Measure memory, then add cycling-regular and cycling-mountain if they fit.
- If the graph build runs out of memory: build the graphs on a machine with more RAM and copy the graph folder to the server.
- HDD is fine: graphs are held in RAM once loaded.
- Expose only the Pisagem backend, through Cloudflare Tunnel (no open router ports). ORS itself stays private.

### Running now (October 2026)

- LXC 126 "ors" (Debian 12, Docker) at 192.168.1.84: OpenRouteService v9.0.0 on port 8080, foot-walking and foot-hiking, Portugal extract, files in /opt/ors (docker-compose.yml, config/ors-config.yml, files/, graphs/). v9 ignored dotted env vars in compose; settings live in config/ors-config.yml.
- Next on the same host: Overpass (wiktorn/overpass-api, port 12345) and Photon (port 2322) with the Portugal extract. Pisagem settings take your own ORS, Overpass and Photon addresses; with your own ORS the per-minute pause is off.
- Still external: map tiles (Esri/CARTO/OpenTopoMap/CyclOSM/Waymarked), IPMA and Open-Meteo (to be cached by the backend).

### All-in-one install (pisagem.sh)

- One-line installer modelled on the owner's Envelo and Maré repos: creates one Debian 12 LXC tagged `pisagem` (nesting, keyctl, 4 cores, 8 GB, 60 GB) with Docker Compose in /opt/pisagem: nginx (page + /ors/, /overpass/, /photon/ proxies), ORS, Overpass (wiktorn), Photon (rtuszik). The page auto-detects /ors/v2/health and uses the same-origin services.
- Run again = update. Finds the hand-made /opt/ors container and offers to convert it (keeps graphs). Inside: `update`, `pisagem status|logs|restart`, autologin and a banner.
- Repo is public (github.com/danielsacosta4/pisagem), no token needed; GITHUB_TOKEN is still honoured if set. `bash test/installer.sh` runs it end to end on fakes in test/fakepve (NET_DIR, MEMINFO, PISAGEM_SOURCE, MAP_URL, BASE override for tests).
- Unverified on the real host yet: Overpass and Photon images/settings, memory with all four services.

### Working with the owner

- Plan first, wait for a go-ahead. Write in English. Owner is not a developer: explain choices by what they change for the user.
- No "how to paste/install" steps when delivering code. End every release with a ready-to-paste commit message.

### Pisagem backend

A small server that serves the page, proxies routing to the private ORS (no API key in the browser), and later serves fire-risk data and user reports.

### Copy what works for Trail Router

From trailrouter.com/blog/how-trail-router-works (2020):

- They self-host a heavily modified OpenRouteService.
- Custom foot profile: favours footways, bridleways, hiking routes and low-speed roads; avoids trunk roads without sidewalks and some primary/secondary roads, especially on bridges and in tunnels.
- Green index: buffer each way by 30 m, score = share of the buffer overlapping parks, forest and water; fed to ORS green weighting as a CSV.
- No repetition: penalise edges already used earlier in the route.
- Loops: candidate points around the perimeters of nearby green space, water and hiking routes; route through them, score on greenness and distance match.

### Test that ends phase 1

Generate 50 routes across 5 regions of Portugal and check each by hand: no main roads, dead ends, roundabout circling or long stretches without sidewalks.

## Later phases

2. Portugal safety (shade and IPMA fire risk are in the prototype; still to do: declared fire alerts and a real high-risk-day test). Owner's point: summer hikes belong in or near forests because they are cooler. So: a "Sombra · Shade" preference that favours tree cover and water on hot days, and only on IPMA level 4–5 days or a declared fire alert keep routes out of forests, with the reason on the ticket. Data: IPMA fire risk by municipality (open JSON, `api.ipma.pt/open-data/forecast/meteorology/rcm/rcm-d{0,1,2}.json`, levels 1–5); keep routes out of forests on very high/maximum risk days and when a fire alert bans forest access; PR/GR first; Portuguese + English. Test: works on a real high fire-risk day.
Also before wider testing: about 10 testers around Porto, a "Report a problem" button to flag bad stretches, short weekly check-ins.
3. Mobile (owner prefers web-only for now): installable app, GPS follow, offline route, saved routes, flag a bad stretch, weather on the route. Test: testers keep using it week after week.
4. Growth: town, trail and tourism partners; paid tier or sponsors.

## Open decisions

- Free public tool vs paid tier.
- Trademark search at INPI before public launch.
