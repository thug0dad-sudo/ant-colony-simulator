#!/usr/bin/env bash
set -e

PROJECT="ant-colony-simulator"

if [ -d "$PROJECT" ]; then
  echo "Folder $PROJECT already exists. Move/delete it first, or run this in another directory."
  exit 1
fi

mkdir -p "$PROJECT"/{client,server,shared,docs,assets/sprites,assets/sounds,tools,tests}

cat > "$PROJECT/requirements.txt" <<'EOF_requirements_txt'
pygame
websockets
EOF_requirements_txt

cat > "$PROJECT/README.md" <<'EOF_README_md'
# Ant Colony Simulator

A SimAnt-inspired ant colony simulator prototype in Python.

## Run

```bash
python3 -m pip install -r requirements.txt
python3 client/pygame_client.py
```

## Current Features

- Workers, soldiers, scouts, larvae, queens
- Food gathering
- Pheromone trails
- Black vs red colony warfare
- Tunnels and rooms
- Basic sector map
- Spider hazard system
- Local playable prototype

## Controls

- Left click: place food
- Right click: spawn ant
- Middle click: dig tunnel
- R: build room
- Space: spawn spider
- Tab: switch player team
- ESC: quit
EOF_README_md

cat > "$PROJECT/CHANGELOG.md" <<'EOF_CHANGELOG_md'
# Changelog

## v0.4-dev

- Created structured project layout.
- Added playable Pygame prototype.
- Added colony, larvae, pheromone, tunnels, rooms, enemies, and spider hazard.
EOF_CHANGELOG_md

cat > "$PROJECT/ROADMAP.md" <<'EOF_ROADMAP_md'
# Roadmap

## v0.5
- Better pathfinding
- Direct-control player ant

## v0.6
- Larger sector map
- Territory conquest

## v0.7
- Multiplayer server/client sync

## v0.8
- House invasion mode
- Human hazards

## v1.0
- Complete SimAnt-inspired playable release
EOF_ROADMAP_md

cat > "$PROJECT/docs/game_design.md" <<'EOF_docs_game_design_md'
# Game Design

This game is inspired by classic ant colony simulation mechanics:
food gathering, pheromone trails, queen defense, enemy colonies, tunnel expansion,
hazards, and territory control.

It should avoid copying original copyrighted art, names, maps, or UI.
EOF_docs_game_design_md

cat > "$PROJECT/shared/constants.py" <<'EOF_shared_constants_py'
WIDTH = 1200
HEIGHT = 800
TILE = 25
FPS = 60
EOF_shared_constants_py

cat > "$PROJECT/server/simulation.py" <<'EOF_server_simulation_py'
import random, math
from shared.constants import WIDTH, HEIGHT, TILE

def dist(a, b):
    return math.hypot(a[0] - b[0], a[1] - b[1])

def clamp(v, lo, hi):
    return max(lo, min(hi, v))

class Larva:
    def __init__(self, team, x, y):
        self.team = team
        self.x = x
        self.y = y
        self.age = 0

    def update(self):
        self.age += 1

class Ant:
    def __init__(self, team, x, y):
        self.team = team
        self.x = x
        self.y = y
        self.vx = random.uniform(-1, 1)
        self.vy = random.uniform(-1, 1)
        self.hp = 100
        self.carrying = False
        self.role = random.choice(["worker", "worker", "soldier", "scout"])
        self.wander_timer = 0

    @property
    def speed(self):
        if self.role == "soldier":
            return 1.45
        if self.role == "scout":
            return 2.05
        return 1.7

    def move_towards(self, target):
        dx = target[0] - self.x
        dy = target[1] - self.y
        length = math.hypot(dx, dy) or 1
        dx = dx / length * self.speed
        dy = dy / length * self.speed
        self.vx = self.vx * 0.9 + dx * 0.1
        self.vy = self.vy * 0.9 + dy * 0.1
        self.x = clamp(self.x + self.vx, 4, WIDTH - 4)
        self.y = clamp(self.y + self.vy, 4, HEIGHT - 4)

    def wander(self):
        self.wander_timer -= 1
        if self.wander_timer <= 0:
            angle = random.random() * math.tau
            self.vx = math.cos(angle) * self.speed
            self.vy = math.sin(angle) * self.speed
            self.wander_timer = random.randint(20, 90)
        self.x = clamp(self.x + self.vx, 4, WIDTH - 4)
        self.y = clamp(self.y + self.vy, 4, HEIGHT - 4)

class Spider:
    def __init__(self, x, y):
        self.x = x
        self.y = y
        self.vx = random.uniform(-1, 1)
        self.vy = random.uniform(-1, 1)
        self.hp = 200
        self.cooldown = 0

    def update(self, ants):
        self.cooldown = max(0, self.cooldown - 1)

        if ants:
            target = min(ants, key=lambda a: dist((self.x, self.y), (a.x, a.y)))
            if dist((self.x, self.y), (target.x, target.y)) < 220:
                dx = target.x - self.x
                dy = target.y - self.y
                length = math.hypot(dx, dy) or 1
                self.vx = self.vx * 0.9 + dx / length * 1.15 * 0.1
                self.vy = self.vy * 0.9 + dy / length * 1.15 * 0.1

                if dist((self.x, self.y), (target.x, target.y)) < 18 and self.cooldown <= 0:
                    target.hp -= 45
                    self.cooldown = 45
            else:
                self.wander()
        else:
            self.wander()

        self.x = clamp(self.x + self.vx, 4, WIDTH - 4)
        self.y = clamp(self.y + self.vy, 4, HEIGHT - 4)

    def wander(self):
        if random.random() < 0.02:
            angle = random.random() * math.tau
            self.vx = math.cos(angle) * 1.1
            self.vy = math.sin(angle) * 1.1

class World:
    def __init__(self):
        self.nest = {
            "black": [180, 560],
            "red": [1000, 180],
        }
        self.queen = {
            "black": [165, 610],
            "red": [1030, 145],
        }
        self.queen_hp = {
            "black": 100,
            "red": 100,
        }
        self.food_storage = {
            "black": 15,
            "red": 15,
        }

        self.tiles = {}
        self.ants = []
        self.foods = []
        self.pheromones = []
        self.larvae = []
        self.spiders = []

        self.tick_count = 0

        for _ in range(35):
            self.spawn_ant("black")
        for _ in range(24):
            self.spawn_ant("red")

        for _ in range(55):
            self.foods.append([random.randint(300, WIDTH - 80), random.randint(50, HEIGHT - 70)])

        for x in range(6, 19):
            self.tiles[f"{x},22"] = "tunnel"
        for y in range(22, 26):
            self.tiles[f"6,{y}"] = "room"

    def spawn_ant(self, team, pos=None):
        p = pos or self.nest[team]
        self.ants.append(Ant(team, p[0], p[1]))

    def place_food(self, x, y):
        self.foods.append([x, y])

    def dig_tunnel(self, x, y):
        self.tiles[f"{int(x // TILE)},{int(y // TILE)}"] = "tunnel"

    def build_room(self, team, x, y):
        if self.food_storage[team] >= 8:
            self.food_storage[team] -= 8
            self.tiles[f"{int(x // TILE)},{int(y // TILE)}"] = "room"

    def add_spider(self, x, y):
        self.spiders.append(Spider(x, y))

    def player_spawn_ant(self, team):
        if self.food_storage[team] >= 3:
            self.food_storage[team] -= 3
            self.spawn_ant(team)

    def update(self):
        self.tick_count += 1

        for p in self.pheromones[:]:
            p[2] -= 1.6
            if p[2] <= 0:
                self.pheromones.remove(p)

        if self.tick_count % 260 == 0:
            for team in ["black", "red"]:
                if self.food_storage[team] > 0 and self.queen_hp[team] > 0:
                    q = self.queen[team]
                    self.larvae.append(Larva(team, q[0] + random.randint(-18, 18), q[1] + random.randint(-18, 18)))
                    self.food_storage[team] -= 1

        for larva in self.larvae[:]:
            larva.update()
            if larva.age > 560:
                self.spawn_ant(larva.team, [larva.x, larva.y])
                self.larvae.remove(larva)

        for spider in self.spiders[:]:
            spider.update(self.ants)
            if spider.hp <= 0:
                self.spiders.remove(spider)

        for ant in self.ants[:]:
            if ant.hp <= 0:
                self.ants.remove(ant)
                continue

            enemy_team = "red" if ant.team == "black" else "black"

            enemies = [a for a in self.ants if a.team != ant.team]
            if enemies:
                enemy = min(enemies, key=lambda e: dist((ant.x, ant.y), (e.x, e.y)))
                if dist((ant.x, ant.y), (enemy.x, enemy.y)) < 14:
                    enemy.hp -= 0.9 if ant.role == "soldier" else 0.35
                    ant.hp -= 0.18

            for spider in self.spiders:
                if dist((ant.x, ant.y), (spider.x, spider.y)) < 16:
                    spider.hp -= 0.35 if ant.role != "soldier" else 0.8

            if ant.carrying:
                ant.move_towards(self.nest[ant.team])
                self.pheromones.append([ant.x, ant.y, 255, ant.team, "food"])
                if dist((ant.x, ant.y), self.nest[ant.team]) < 36:
                    ant.carrying = False
                    self.food_storage[ant.team] += 1
                continue

            if dist((ant.x, ant.y), self.queen[enemy_team]) < 32:
                self.queen_hp[enemy_team] -= 0.03

            nearby_food = [f for f in self.foods if dist((ant.x, ant.y), f) < 185]
            if nearby_food:
                food = min(nearby_food, key=lambda f: dist((ant.x, ant.y), f))
                ant.move_towards(food)
                if dist((ant.x, ant.y), food) < 10:
                    self.foods.remove(food)
                    ant.carrying = True
                continue

            trails = [
                p for p in self.pheromones
                if p[3] == ant.team and dist((ant.x, ant.y), (p[0], p[1])) < 80
            ]

            if trails and random.random() < 0.58:
                trail = max(trails, key=lambda p: p[2])
                ant.move_towards([trail[0], trail[1]])
            elif ant.team == "red" and random.random() < 0.35:
                ant.move_towards(self.queen["black"])
            else:
                ant.wander()
EOF_server_simulation_py

cat > "$PROJECT/client/pygame_client.py" <<'EOF_client_pygame_client_py'
import sys, os
sys.path.append(os.path.dirname(os.path.dirname(__file__)))

import pygame
from shared.constants import WIDTH, HEIGHT, TILE, FPS
from server.simulation import World

pygame.init()
screen = pygame.display.set_mode((WIDTH, HEIGHT))
pygame.display.set_caption("Ant Colony Simulator - Local Prototype")
clock = pygame.time.Clock()
font = pygame.font.SysFont(None, 25)
big = pygame.font.SysFont(None, 46)

COLORS = {
    "grass": (45, 95, 45),
    "dirt": (56, 42, 25),
    "house": (90, 82, 72),
    "tunnel": (96, 66, 36),
    "room": (130, 88, 45),
    "black": (18, 18, 18),
    "red": (178, 35, 25),
    "food": (70, 205, 82),
    "pher": (70, 150, 255),
    "text": (245, 235, 210),
    "queen": (45, 20, 20),
    "larva": (245, 220, 155),
    "spider": (75, 35, 80),
}

world = World()
player_team = "black"

def base_tile(x, y):
    if y < HEIGHT // TILE // 2:
        if x > WIDTH // TILE - 9:
            return "house"
        return "grass"
    return "dirt"

def draw_world():
    for y in range(HEIGHT // TILE):
        for x in range(WIDTH // TILE):
            kind = world.tiles.get(f"{x},{y}", base_tile(x, y))
            pygame.draw.rect(screen, COLORS[kind], (x * TILE, y * TILE, TILE, TILE))

def draw():
    draw_world()

    for p in world.pheromones[-700:]:
        pygame.draw.circle(screen, COLORS["pher"], (int(p[0]), int(p[1])), 2)

    for f in world.foods:
        pygame.draw.circle(screen, COLORS["food"], (int(f[0]), int(f[1])), 7)

    for team, pos in world.queen.items():
        pygame.draw.circle(screen, COLORS["queen"], (int(pos[0]), int(pos[1])), 18)
        pygame.draw.circle(screen, COLORS[team], (int(pos[0]), int(pos[1])), 8)

    for larva in world.larvae:
        pygame.draw.circle(screen, COLORS["larva"], (int(larva.x), int(larva.y)), 4)

    for spider in world.spiders:
        pygame.draw.circle(screen, COLORS["spider"], (int(spider.x), int(spider.y)), 13)
        pygame.draw.circle(screen, (20, 10, 20), (int(spider.x), int(spider.y)), 5)

    for ant in world.ants:
        color = COLORS[ant.team]
        radius = 6 if ant.role == "soldier" else 5
        if ant.role == "scout":
            radius = 4
        pygame.draw.circle(screen, color, (int(ant.x), int(ant.y)), radius)
        if ant.carrying:
            pygame.draw.circle(screen, COLORS["food"], (int(ant.x), int(ant.y - 8)), 3)

    hud = (
        f"Team: {player_team.upper()} | "
        f"Black Queen: {int(world.queen_hp['black'])} | "
        f"Red Queen: {int(world.queen_hp['red'])} | "
        f"Black Food: {world.food_storage['black']} | "
        f"Red Food: {world.food_storage['red']} | "
        f"Ants: {len(world.ants)} | Spiders: {len(world.spiders)}"
    )
    controls = "Left food | Right spawn ant | Middle tunnel | R room | Space spider | Tab switch team | ESC quit"

    screen.blit(font.render(hud, True, COLORS["text"]), (18, 18))
    screen.blit(font.render(controls, True, COLORS["text"]), (18, 46))

    if world.queen_hp["black"] <= 0:
        screen.blit(big.render("RED COLONY WINS", True, (255, 90, 80)), (430, 370))
    if world.queen_hp["red"] <= 0:
        screen.blit(big.render("BLACK COLONY WINS", True, (255, 90, 80)), (405, 410))

    pygame.display.flip()

running = True
while running:
    clock.tick(FPS)

    for event in pygame.event.get():
        if event.type == pygame.QUIT:
            running = False

        elif event.type == pygame.KEYDOWN:
            if event.key == pygame.K_ESCAPE:
                running = False
            elif event.key == pygame.K_TAB:
                player_team = "red" if player_team == "black" else "black"
            elif event.key == pygame.K_r:
                x, y = pygame.mouse.get_pos()
                world.build_room(player_team, x, y)
            elif event.key == pygame.K_SPACE:
                x, y = pygame.mouse.get_pos()
                world.add_spider(x, y)

        elif event.type == pygame.MOUSEBUTTONDOWN:
            x, y = event.pos
            if event.button == 1:
                world.place_food(x, y)
            elif event.button == 3:
                world.player_spawn_ant(player_team)
            elif event.button == 2:
                world.dig_tunnel(x, y)

    if world.queen_hp["black"] > 0 and world.queen_hp["red"] > 0:
        world.update()

    draw()

pygame.quit()
EOF_client_pygame_client_py

cat > "$PROJECT/server/server.py" <<'EOF_server_server_py'
"""
Placeholder for the future authoritative multiplayer server.

Next step:
- Move World.update() here.
- Broadcast snapshots over websockets.
- Let clients send commands only.
"""
EOF_server_server_py

cat > "$PROJECT/tools/run_local.sh" <<'EOF_tools_run_local_sh'
#!/usr/bin/env bash
python3 client/pygame_client.py
EOF_tools_run_local_sh

cat > "$PROJECT/.gitignore" <<'EOF__gitignore'
__pycache__/
*.pyc
.venv/
.DS_Store
EOF__gitignore

chmod +x "$PROJECT/tools/run_local.sh"

echo
echo "Created $PROJECT"
echo
echo "Run it:"
echo "cd $PROJECT"
echo "python3 -m pip install -r requirements.txt"
echo "python3 client/pygame_client.py"
