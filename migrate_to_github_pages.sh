#!/usr/bin/env bash
set -e

# Run this from the root of your ant-colony-simulator repo.
# It adds a browser-playable GitHub Pages version.

if [ ! -d ".git" ]; then
  echo "This does not look like a Git repo. cd into your ant-colony-simulator repo first."
  exit 1
fi

mkdir -p web docs

cat > index.html <<'EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Ant Colony Simulator</title>
  <link rel="stylesheet" href="web/style.css" />
</head>
<body>
  <main>
    <header>
      <h1>Ant Colony Simulator</h1>
      <p>A browser-playable ant colony simulator inspired by classic colony games.</p>
    </header>

    <section id="hud">
      <div id="stats">Loading...</div>
      <div id="controls">
        Left click: place food · Right click: spawn ant · Middle click: dig tunnel · R: room · Space: spider · Tab: switch team
      </div>
    </section>

    <canvas id="game" width="1200" height="800"></canvas>

    <footer>
      <p>
        Prototype build for GitHub Pages.
        <a href="https://github.com/thug0dad-sudo/ant-colony-simulator">Source code</a>
      </p>
    </footer>
  </main>

  <script src="web/game.js"></script>
</body>
</html>

EOF

cat > web/style.css <<'EOF'
* {
  box-sizing: border-box;
}

body {
  margin: 0;
  background: #18130d;
  color: #f5ebd2;
  font-family: system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif;
}

main {
  width: min(1220px, 100vw);
  margin: 0 auto;
  padding: 16px;
}

header {
  display: flex;
  justify-content: space-between;
  gap: 16px;
  align-items: end;
  flex-wrap: wrap;
}

h1 {
  margin: 0;
  font-size: 32px;
}

p {
  margin: 6px 0;
}

#hud {
  margin: 12px 0;
  padding: 12px;
  border: 1px solid #5c4328;
  background: #241a10;
  border-radius: 12px;
}

#stats {
  font-weight: 700;
  margin-bottom: 6px;
}

#controls {
  opacity: 0.85;
  font-size: 14px;
}

canvas {
  display: block;
  width: 100%;
  height: auto;
  max-height: calc(100vh - 210px);
  border: 2px solid #5c4328;
  border-radius: 14px;
  background: #382a19;
  image-rendering: auto;
}

a {
  color: #85d7ff;
}

EOF

cat > web/game.js <<'EOF'
const canvas = document.getElementById("game");
const ctx = canvas.getContext("2d");
const statsEl = document.getElementById("stats");

const WIDTH = canvas.width;
const HEIGHT = canvas.height;
const TILE = 25;

const COLORS = {
  grass: "#2d5f2d",
  dirt: "#382a19",
  house: "#5a5248",
  tunnel: "#604224",
  room: "#82582d",
  black: "#121212",
  red: "#b22319",
  food: "#46cd52",
  pher: "rgba(70,150,255,0.55)",
  text: "#f5ebd2",
  queen: "#2d1414",
  larva: "#f5dc9b",
  spider: "#4b2350",
  selected: "#ffd166"
};

function rand(min, max) {
  return Math.random() * (max - min) + min;
}

function randi(min, max) {
  return Math.floor(rand(min, max + 1));
}

function dist(a, b) {
  return Math.hypot(a.x - b.x, a.y - b.y);
}

function clamp(v, lo, hi) {
  return Math.max(lo, Math.min(hi, v));
}

class Ant {
  constructor(team, x, y) {
    this.team = team;
    this.x = x;
    this.y = y;
    this.vx = rand(-1, 1);
    this.vy = rand(-1, 1);
    this.hp = 100;
    this.carrying = false;
    this.role = Math.random() < 0.2 ? "soldier" : Math.random() < 0.2 ? "scout" : "worker";
    this.wanderTimer = 0;
  }

  get speed() {
    if (this.role === "soldier") return 1.45;
    if (this.role === "scout") return 2.05;
    return 1.7;
  }

  moveTowards(target) {
    let dx = target.x - this.x;
    let dy = target.y - this.y;
    const len = Math.hypot(dx, dy) || 1;
    dx = (dx / len) * this.speed;
    dy = (dy / len) * this.speed;

    this.vx = this.vx * 0.9 + dx * 0.1;
    this.vy = this.vy * 0.9 + dy * 0.1;

    this.x = clamp(this.x + this.vx, 4, WIDTH - 4);
    this.y = clamp(this.y + this.vy, 4, HEIGHT - 4);
  }

  wander() {
    this.wanderTimer -= 1;
    if (this.wanderTimer <= 0) {
      const angle = Math.random() * Math.PI * 2;
      this.vx = Math.cos(angle) * this.speed;
      this.vy = Math.sin(angle) * this.speed;
      this.wanderTimer = randi(20, 90);
    }

    this.x = clamp(this.x + this.vx, 4, WIDTH - 4);
    this.y = clamp(this.y + this.vy, 4, HEIGHT - 4);
  }
}

class Larva {
  constructor(team, x, y) {
    this.team = team;
    this.x = x;
    this.y = y;
    this.age = 0;
  }

  update() {
    this.age += 1;
  }
}

class Spider {
  constructor(x, y) {
    this.x = x;
    this.y = y;
    this.vx = rand(-1, 1);
    this.vy = rand(-1, 1);
    this.hp = 200;
    this.cooldown = 0;
  }

  update(ants) {
    this.cooldown = Math.max(0, this.cooldown - 1);

    if (ants.length > 0) {
      let target = ants.reduce((best, ant) => {
        return dist(this, ant) < dist(this, best) ? ant : best;
      }, ants[0]);

      if (dist(this, target) < 220) {
        let dx = target.x - this.x;
        let dy = target.y - this.y;
        const len = Math.hypot(dx, dy) || 1;
        this.vx = this.vx * 0.9 + (dx / len) * 1.15 * 0.1;
        this.vy = this.vy * 0.9 + (dy / len) * 1.15 * 0.1;

        if (dist(this, target) < 18 && this.cooldown <= 0) {
          target.hp -= 45;
          this.cooldown = 45;
        }
      } else {
        this.wander();
      }
    } else {
      this.wander();
    }

    this.x = clamp(this.x + this.vx, 4, WIDTH - 4);
    this.y = clamp(this.y + this.vy, 4, HEIGHT - 4);
  }

  wander() {
    if (Math.random() < 0.02) {
      const angle = Math.random() * Math.PI * 2;
      this.vx = Math.cos(angle) * 1.1;
      this.vy = Math.sin(angle) * 1.1;
    }
  }
}

class World {
  constructor() {
    this.nest = {
      black: { x: 180, y: 560 },
      red: { x: 1000, y: 180 }
    };

    this.queen = {
      black: { x: 165, y: 610 },
      red: { x: 1030, y: 145 }
    };

    this.queenHp = {
      black: 100,
      red: 100
    };

    this.foodStorage = {
      black: 15,
      red: 15
    };

    this.tiles = new Map();
    this.ants = [];
    this.foods = [];
    this.pheromones = [];
    this.larvae = [];
    this.spiders = [];
    this.tick = 0;

    for (let i = 0; i < 35; i++) this.spawnAnt("black");
    for (let i = 0; i < 24; i++) this.spawnAnt("red");

    for (let i = 0; i < 55; i++) {
      this.foods.push({ x: randi(300, WIDTH - 80), y: randi(50, HEIGHT - 70) });
    }

    for (let x = 6; x < 19; x++) this.tiles.set(`${x},22`, "tunnel");
    for (let y = 22; y < 26; y++) this.tiles.set(`6,${y}`, "room");
  }

  spawnAnt(team, pos = null) {
    const p = pos || this.nest[team];
    this.ants.push(new Ant(team, p.x, p.y));
  }

  playerSpawnAnt(team) {
    if (this.foodStorage[team] >= 3) {
      this.foodStorage[team] -= 3;
      this.spawnAnt(team);
    }
  }

  placeFood(x, y) {
    this.foods.push({ x, y });
  }

  digTunnel(x, y) {
    this.tiles.set(`${Math.floor(x / TILE)},${Math.floor(y / TILE)}`, "tunnel");
  }

  buildRoom(team, x, y) {
    if (this.foodStorage[team] >= 8) {
      this.foodStorage[team] -= 8;
      this.tiles.set(`${Math.floor(x / TILE)},${Math.floor(y / TILE)}`, "room");
    }
  }

  addSpider(x, y) {
    this.spiders.push(new Spider(x, y));
  }

  update() {
    this.tick += 1;

    this.pheromones = this.pheromones
      .map(p => ({ ...p, strength: p.strength - 1.6 }))
      .filter(p => p.strength > 0);

    if (this.tick % 260 === 0) {
      for (const team of ["black", "red"]) {
        if (this.foodStorage[team] > 0 && this.queenHp[team] > 0) {
          const q = this.queen[team];
          this.larvae.push(new Larva(team, q.x + randi(-18, 18), q.y + randi(-18, 18)));
          this.foodStorage[team] -= 1;
        }
      }
    }

    for (const larva of [...this.larvae]) {
      larva.update();
      if (larva.age > 560) {
        this.spawnAnt(larva.team, larva);
        this.larvae.splice(this.larvae.indexOf(larva), 1);
      }
    }

    for (const spider of [...this.spiders]) {
      spider.update(this.ants);
      if (spider.hp <= 0) this.spiders.splice(this.spiders.indexOf(spider), 1);
    }

    for (const ant of [...this.ants]) {
      if (ant.hp <= 0) {
        this.ants.splice(this.ants.indexOf(ant), 1);
        continue;
      }

      const enemyTeam = ant.team === "black" ? "red" : "black";
      const enemies = this.ants.filter(a => a.team !== ant.team);

      if (enemies.length) {
        const enemy = enemies.reduce((best, e) => dist(ant, e) < dist(ant, best) ? e : best, enemies[0]);
        if (dist(ant, enemy) < 14) {
          enemy.hp -= ant.role === "soldier" ? 0.9 : 0.35;
          ant.hp -= 0.18;
        }
      }

      for (const spider of this.spiders) {
        if (dist(ant, spider) < 16) {
          spider.hp -= ant.role === "soldier" ? 0.8 : 0.35;
        }
      }

      if (ant.carrying) {
        ant.moveTowards(this.nest[ant.team]);
        this.pheromones.push({ x: ant.x, y: ant.y, strength: 255, team: ant.team, kind: "food" });

        if (dist(ant, this.nest[ant.team]) < 36) {
          ant.carrying = false;
          this.foodStorage[ant.team] += 1;
        }
        continue;
      }

      if (dist(ant, this.queen[enemyTeam]) < 32) {
        this.queenHp[enemyTeam] -= 0.03;
      }

      const nearbyFood = this.foods.filter(f => dist(ant, f) < 185);
      if (nearbyFood.length) {
        const food = nearbyFood.reduce((best, f) => dist(ant, f) < dist(ant, best) ? f : best, nearbyFood[0]);
        ant.moveTowards(food);

        if (dist(ant, food) < 10) {
          this.foods.splice(this.foods.indexOf(food), 1);
          ant.carrying = true;
        }
        continue;
      }

      const trails = this.pheromones.filter(p => p.team === ant.team && dist(ant, p) < 80);
      if (trails.length && Math.random() < 0.58) {
        const trail = trails.reduce((best, p) => p.strength > best.strength ? p : best, trails[0]);
        ant.moveTowards(trail);
      } else if (ant.team === "red" && Math.random() < 0.35) {
        ant.moveTowards(this.queen.black);
      } else {
        ant.wander();
      }
    }
  }
}

const world = new World();
let playerTeam = "black";
let mouse = { x: 0, y: 0 };

function baseTile(x, y) {
  if (y < HEIGHT / TILE / 2) {
    if (x > WIDTH / TILE - 9) return "house";
    return "grass";
  }
  return "dirt";
}

function drawWorld() {
  for (let y = 0; y < HEIGHT / TILE; y++) {
    for (let x = 0; x < WIDTH / TILE; x++) {
      const kind = world.tiles.get(`${x},${y}`) || baseTile(x, y);
      ctx.fillStyle = COLORS[kind];
      ctx.fillRect(x * TILE, y * TILE, TILE, TILE);
    }
  }
}

function drawCircle(x, y, r, color) {
  ctx.beginPath();
  ctx.fillStyle = color;
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fill();
}

function draw() {
  drawWorld();

  for (const p of world.pheromones.slice(-700)) {
    drawCircle(p.x, p.y, 2, COLORS.pher);
  }

  for (const f of world.foods) {
    drawCircle(f.x, f.y, 7, COLORS.food);
  }

  for (const team of ["black", "red"]) {
    const q = world.queen[team];
    drawCircle(q.x, q.y, 18, COLORS.queen);
    drawCircle(q.x, q.y, 8, COLORS[team]);
  }

  for (const larva of world.larvae) {
    drawCircle(larva.x, larva.y, 4, COLORS.larva);
  }

  for (const spider of world.spiders) {
    drawCircle(spider.x, spider.y, 13, COLORS.spider);
    drawCircle(spider.x, spider.y, 5, "#140a14");
  }

  for (const ant of world.ants) {
    let radius = ant.role === "soldier" ? 6 : 5;
    if (ant.role === "scout") radius = 4;
    drawCircle(ant.x, ant.y, radius, COLORS[ant.team]);

    if (ant.carrying) {
      drawCircle(ant.x, ant.y - 8, 3, COLORS.food);
    }
  }

  if (world.queenHp.black <= 0 || world.queenHp.red <= 0) {
    ctx.fillStyle = "rgba(0,0,0,0.45)";
    ctx.fillRect(0, 0, WIDTH, HEIGHT);
    ctx.fillStyle = "#ff5a50";
    ctx.font = "48px system-ui";
    ctx.textAlign = "center";
    ctx.fillText(world.queenHp.black <= 0 ? "RED COLONY WINS" : "BLACK COLONY WINS", WIDTH / 2, HEIGHT / 2);
    ctx.textAlign = "start";
  }

  statsEl.textContent =
    `Team: ${playerTeam.toUpperCase()} | ` +
    `Black Queen: ${Math.floor(world.queenHp.black)} | ` +
    `Red Queen: ${Math.floor(world.queenHp.red)} | ` +
    `Black Food: ${world.foodStorage.black} | ` +
    `Red Food: ${world.foodStorage.red} | ` +
    `Ants: ${world.ants.length} | Spiders: ${world.spiders.length}`;
}

function getCanvasPos(event) {
  const rect = canvas.getBoundingClientRect();
  return {
    x: ((event.clientX - rect.left) / rect.width) * canvas.width,
    y: ((event.clientY - rect.top) / rect.height) * canvas.height
  };
}

canvas.addEventListener("mousemove", e => {
  mouse = getCanvasPos(e);
});

canvas.addEventListener("contextmenu", e => e.preventDefault());

canvas.addEventListener("mousedown", e => {
  const pos = getCanvasPos(e);
  if (e.button === 0) world.placeFood(pos.x, pos.y);
  if (e.button === 2) world.playerSpawnAnt(playerTeam);
  if (e.button === 1) world.digTunnel(pos.x, pos.y);
});

window.addEventListener("keydown", e => {
  if (e.key === "Tab") {
    e.preventDefault();
    playerTeam = playerTeam === "black" ? "red" : "black";
  }

  if (e.key.toLowerCase() === "r") {
    world.buildRoom(playerTeam, mouse.x, mouse.y);
  }

  if (e.code === "Space") {
    e.preventDefault();
    world.addSpider(mouse.x, mouse.y);
  }
});

function loop() {
  if (world.queenHp.black > 0 && world.queenHp.red > 0) {
    world.update();
  }
  draw();
  requestAnimationFrame(loop);
}

loop();

EOF

cat > docs/browser_migration.md <<'EOF'
# Browser Migration

This folder contains the GitHub Pages playable version.

No build step is needed. GitHub Pages can serve:

- `index.html`
- `web/style.css`
- `web/game.js`

Recommended Pages settings:

- Source: Deploy from branch
- Branch: main
- Folder: / root

Final URL:

https://thug0dad-sudo.github.io/ant-colony-simulator/

EOF

git add index.html web/style.css web/game.js docs/browser_migration.md
git commit -m "Add browser playable GitHub Pages version"

echo
echo "Browser version added."
echo
echo "Push it with:"
echo "git push origin main"
echo
echo "Then enable GitHub Pages:"
echo "Settings > Pages > Deploy from branch > main > / root"
echo
echo "URL:"
echo "https://thug0dad-sudo.github.io/ant-colony-simulator/"
