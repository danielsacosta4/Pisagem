# Pisagem

Random loop routes for walking, hiking, road cycling and mountain biking in Portugal.

## Install on Proxmox

On the Proxmox host shell:

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/danielsacosta4/pisagem/main/pisagem.sh)"
```

It creates one Debian 12 container (tag `pisagem`, 4 cores, 8 GB, 60 GB) running, behind one web address:

- the Pisagem page (nginx, port 80)
- OpenRouteService (walking and hiking), Overpass and Photon, all with the Portugal map

Running it again updates that container. If it finds the earlier hand-made OpenRouteService container (`/opt/ors`), it offers to convert it and keeps the routes it already built.

Inside the container: `update` gets the latest version, `pisagem status` checks each service, `pisagem logs`, `pisagem restart`.

The first start takes a while: the route network, Overpass database and search index are built from the map (an hour or more).

## Layout

- `web/pisagem.html` – the app (one file)
- `server/` – docker-compose.yml, nginx.conf, ors-config.yml
- `pisagem.sh` – the installer
- `test/installer.sh` – runs the installer against a fake Proxmox (as root, in a throwaway environment)
