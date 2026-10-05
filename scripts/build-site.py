#!/usr/bin/env python3
"""Writes the website's game pages, its sitemap and the game links on every page.

The covers on the home page (docs/index.html) hold each game's art, renderer and recipe;
GAMES below holds the words for the game's own page. Run this after changing either,
then commit what it writes:

    scripts/build-site.py
"""
import datetime
import html
import json
import re
from html.parser import HTMLParser
from pathlib import Path

DOCS = Path(__file__).resolve().parent.parent / "docs"
SITE = "https://tarikbc.github.io/macgames/"
RELEASES = "https://github.com/tarikbc/macgames/releases/latest"
REPO = "https://github.com/tarikbc/macgames"
STYLE, SCRIPT = "assets/css/style.css?v=7", "assets/js/site.js?v=6"
GITHUB_ICON = ""  # copied from the home page header in main()

SHARED_STEAM = ("One Steam for your games",
                "The game installs into the shared Steam library, so you sign in to Steam once for all your games.")
D3DMETAL = ("DirectX through Metal", "Apple's D3DMetal turns the game's DirectX calls into Metal.")
STEAM = {"store": "Steam", "account": "Steam"}
BATTLENET = {"store": "Battle.net", "account": "Battle.net"}
ROCKSTAR_STEPS = "Steam opens. Sign in, then install {name} and keep the default folder. The Rockstar Games Launcher asks you to sign in the first time you play."

# The words for each game's page, in the order of the home page covers.
GAMES = {
    "aoe4": dict(STEAM, slug="age-of-empires-iv", also="AoE4",
        lead="MacGames runs Age of Empires IV on Apple silicon Macs. It sets up Steam in a Windows environment, turns the game's DirectX 12 into Metal, and runs its x87 math through x87sidecar.",
        tested="Tested on a Mac", where="Steam, in the shared Steam library",
        does=[("Fast x87 math", "Age of Empires IV uses old x87 math, which Rosetta 2 translates slowly. On the game build it was made for, the game runs under x87sidecar, which translates that math much faster. Any other build falls back to standard Wine on its own."),
              ("DirectX 12 through Metal", "Apple's D3DMetal turns the game's DirectX 12 calls into Metal."),
              ("Game controllers", "Controllers work through SDL, also when the game window is in the back."),
              ("Settings on its page", "Turn the x87 optimization and the Metal performance HUD on or off on the game's page in MacGames.")]),
    "cs2": dict(STEAM, slug="counter-strike-2", also="CS2",
        lead="MacGames runs Counter-Strike 2 on Apple silicon Macs with DXMT, which turns DirectX 11 into Metal. Shaders compile before the match, and the first launch opens a window that fits your display.",
        tested="Tested on a Mac: it reaches the main menu", where="Steam, in the shared Steam library",
        online="Counter-Strike 2 uses VAC. Online play with anti-cheat is at your own risk.",
        does=[("DirectX 11 on Metal", "A build of DXMT made for Counter-Strike 2 translates the game's DirectX 11 into Metal."),
              ("Shaders before the match", "Shaders and pipelines compile early and stay in a cache between sessions, so they are ready when the match needs them."),
              ("A window that fits", "The first launch opens a borderless window at your display's size. Reset display on the game's page does it again."),
              ("Performance HUD", "Turn the Metal performance HUD on or off on the game's page.")]),
    "aoe3": dict(STEAM, slug="age-of-empires-iii-definitive-edition", also="AoE3 DE", short="Age of Empires III: DE",
        lead="MacGames runs Age of Empires III: Definitive Edition on Apple silicon Macs. It sets up Steam, turns the game's DirectX into Metal and skips the game's hardware check.",
        where="Steam, in the shared Steam library",
        does=[D3DMETAL,
              ("No hardware warning", "MacGames sets the registry values that skip the game's unsupported-system check and its first-run hardware setup."),
              ("Its files kept apart", "The game keeps its home, cache and settings folders inside its own MacGames folder."),
              SHARED_STEAM]),
    "aom-retold": dict(STEAM, slug="age-of-mythology-retold", also="AoM Retold",
        lead="MacGames runs Age of Mythology: Retold on Apple silicon Macs. It sets up Steam, turns the game's DirectX into Metal and keeps fullscreen below the notch.",
        where="Steam, in the shared Steam library",
        does=[D3DMETAL,
              ("GPU entries that match", "The game checks its graphics card in registry keys that Wine fills in. A small helper makes those keys match the GPU that D3DMetal reports."),
              ("Fullscreen below the notch", "On a MacBook with a notch, the game's fullscreen sits below the notch, so no part of the game is hidden."),
              SHARED_STEAM]),
    "coh3": dict(STEAM, slug="company-of-heroes-3", also="CoH3",
        lead="MacGames runs Company of Heroes 3 on Apple silicon Macs. It sets up Steam, turns the game's DirectX into Metal and adds the Microsoft runtime that multiplayer needs.",
        where="Steam, in the shared Steam library",
        does=[D3DMETAL,
              ("Ready for multiplayer", "Multiplayer needs Microsoft's Universal C Runtime. MacGames installs it for this game only, and every other program keeps Wine's own."),
              SHARED_STEAM]),
    "zero-hour": dict(STEAM, slug="command-and-conquer-generals-zero-hour", also="C&C Generals Zero Hour", short="C&C Generals Zero Hour",
        lead="MacGames runs Command & Conquer: Generals Zero Hour on Apple silicon Macs. It sets up Steam and the game's resolution, and starts GeneralsOnline for online play.",
        where="Steam, in the shared Steam library",
        online="Play Online sets up and starts GeneralsOnline, the community's online service for Zero Hour.",
        does=[("Direct3D 8 through Wine", "Wine draws the game's Direct3D 8 graphics with its own renderer."),
              ("Play Online", "One button sets up and starts GeneralsOnline, the community's online service for Zero Hour."),
              ("Resolution set to your display", "The first launch sets the game's resolution to your display, from 800 x 600 up to 1920 x 1200, and turns on edge scrolling and cursor capture."),
              SHARED_STEAM]),
    "red-alert2": dict(STEAM, slug="command-and-conquer-red-alert-2", also="C&C Red Alert 2", short="C&C Red Alert 2",
        lead="MacGames runs Command & Conquer: Red Alert 2 on Apple silicon Macs. It draws the game through cnc-ddraw, sizes it to your display and starts CnCNet for online play.",
        where="Steam, in the shared Steam library",
        online="Play Online sets up and starts CnCNet, the community's online service for the classic Command & Conquer games.",
        does=[("cnc-ddraw", "cnc-ddraw draws the game's DirectDraw graphics, scaled cleanly to your display."),
              ("Play Online", "One button sets up and starts CnCNet, the community's online service for the classic Command & Conquer games."),
              ("Resolution set to your display", "The game starts at your display's size, up to 1920 x 1200."),
              ("Saves kept", "Your saved games and settings stay when you uninstall the game.")]),
    "heroes3": dict(STEAM, slug="heroes-of-might-and-magic-iii", also="HoMM3",
        lead="MacGames runs Heroes of Might and Magic III on Apple silicon Macs. It draws the game through cnc-ddraw, repairs its sound and keeps your saves.",
        where="Steam, in the shared Steam library",
        does=[("cnc-ddraw", "cnc-ddraw draws the game's graphics, scaled cleanly to your display."),
              ("A fix for the sound", "MacGames repairs the game's sound library, MSS32.DLL, and keeps a copy of the original."),
              ("Saves kept", "Your saved games stay when you uninstall the game."),
              SHARED_STEAM]),
    "diablo4": dict(STEAM, slug="diablo-iv", also="Diablo 4", macos="26.5",
        lead="MacGames runs Diablo IV from Steam on Apple silicon Macs. It sets up Steam and turns the game's DirectX 12 into Metal through Apple's D3DMetal.",
        where="Steam, in the shared Steam library",
        does=[("DirectX 12 through Metal", "Apple's D3DMetal turns the game's DirectX 12 calls into Metal, with the shared D3DMetal library the game needs."),
              SHARED_STEAM,
              ("Also on Battle.net", "Bought Diablo IV on Battle.net instead? MacGames has a Battle.net version of this game too.")]),
    "poe2": dict(STEAM, slug="path-of-exile-2", also="PoE 2", macos="26.5",
        lead="MacGames runs Path of Exile 2 on Apple silicon Macs. It sets up Steam, picks the game's DirectX 12 renderer for D3DMetal and tunes Wine for the game.",
        where="Steam, in the shared Steam library",
        does=[("DirectX 12 through Metal", "MacGames sets the game's renderer to DirectX 12, which Apple's D3DMetal turns into Metal."),
              ("Display settings that suit the Mac", "The first launch uses borderless fullscreen in a maximized window, with engine multithreading on. Settings you choose yourself stay."),
              ("Wine tuned for the game", "Wine's msync is off for this game, which needs Wine's other sync method."),
              SHARED_STEAM]),
    "hogwarts-legacy": dict(STEAM, slug="hogwarts-legacy", macos="26.5",
        lead="MacGames runs Hogwarts Legacy on Apple silicon Macs. It sets up Steam, turns the game's DirectX into Metal and turns off the game's driver warning.",
        where="Steam, in the shared Steam library",
        does=[D3DMETAL,
              ("A shader cache of its own", "The game's Metal shaders stay in a cache folder of their own between sessions."),
              ("No driver warning", "The game's warning about an unsupported AMD driver is turned off, so it does not show on every start."),
              SHARED_STEAM]),
    "witcher3": dict(STEAM, slug="the-witcher-3-wild-hunt", also="Witcher 3",
        lead="MacGames runs The Witcher 3: Wild Hunt on Apple silicon Macs. It sets up Steam, turns the game's DirectX 12 into Metal and stops a shader crash with a small proxy.",
        where="Steam, in the shared Steam library",
        does=[("DirectX 12 through Metal", "Apple's D3DMetal turns the game's DirectX 12 calls into Metal."),
              ("A fix for a shader crash", "A small proxy for the game's AMD FidelityFX loader refuses the pipelines that Apple's shader converter cannot build. The original file is kept."),
              ("Straight into the game", "The game reports Windows 11 and skips its own launcher."),
              SHARED_STEAM]),
    "elden-ring": dict(STEAM, slug="elden-ring",
        lead="MacGames runs Elden Ring on Apple silicon Macs, offline. It sets up Steam, installs the Windows runtimes the game needs and turns its DirectX 12 into Metal.",
        where="Steam, in the shared Steam library",
        online="Elden Ring starts directly in offline mode, because its anti-cheat does not run on Wine. Online play is off.",
        does=[("DirectX 12 through Metal", "Apple's D3DMetal turns the game's DirectX 12 calls into Metal."),
              ("Windows runtimes installed for you", "The first launch installs the Microsoft Visual C++ runtimes the game needs, from Steam's own copies."),
              ("Offline play", "The game starts directly, without its anti-cheat, so it runs in offline mode."),
              SHARED_STEAM]),
    "skyrim-se": dict(STEAM, slug="skyrim-special-edition", also="Skyrim SE", short="Skyrim Special Edition",
        lead="MacGames runs The Elder Scrolls V: Skyrim Special Edition on Apple silicon Macs. It gives the game its own Steam and Windows environment, with DXMT 0.72 for DirectX 11.",
        where="Steam, in an environment of its own",
        does=[("DirectX 11 on Metal", "DXMT 0.72 translates the game's DirectX 11 into Metal, with a shader cache of its own."),
              ("An environment of its own", "Skyrim gets its own Steam, engine and drives, so its setup never changes your other games."),
              ("Its files kept apart", "The game's cache and settings folders stay inside its own MacGames folder.")]),
    "overwatch": dict(BATTLENET, slug="overwatch", also="once called Overwatch 2", free=True,
        meta="It runs on Recall's Wine and DXMT, made for Overwatch (once Overwatch 2), and starts through Battle.net.",
        lead="MacGames runs Overwatch on Apple silicon Macs with the Wine and DXMT build of Recall, an open-source project made for this game. Battle.net starts the game when you press Play.",
        where="Battle.net, in an environment of its own",
        online="Overwatch is online only. Online play with anti-cheat is at your own risk.",
        credit='The engine comes from <a href="https://github.com/AsherJN/recall">Recall</a>, unchanged. Thanks to its author.',
        does=[("Recall's engine", "Overwatch runs on Recall 1.1's Wine and DXMT, byte for byte as Recall ships them, with Recall's settings."),
              ("Raw mouse input and Game Mode", "Mouse look reads raw input, and macOS Game Mode turns on while you play."),
              ("Pipelines before each session", "Recall's tool prepares the game's graphics pipelines before Battle.net starts, so fewer compile mid-match."),
              ("A resolution that fits", "Before each start, MacGames writes the game's resolution and DXMT's fullscreen canvas, and lowers a size that does not fit your display.")]),
    "diablo4-battlenet": dict(BATTLENET, slug="diablo-iv-battle-net", page_name="Diablo IV from Battle.net", game="Diablo IV", short="Diablo IV from Battle.net", macos="26.5",
        lead="MacGames runs the Battle.net version of Diablo IV on Apple silicon Macs. It sets up Battle.net in a Windows environment and turns the game's DirectX 12 into Metal.",
        where="Battle.net, shared with Diablo II: Resurrected",
        does=[("DirectX 12 through Metal", "Apple's D3DMetal turns the game's DirectX 12 calls into Metal."),
              ("A Battle.net that works", "The Battle.net app draws through DXMT, and MacGames brings its window back when it hides."),
              ("One Battle.net for Blizzard games", "Diablo IV and Diablo II: Resurrected share one Battle.net, so you sign in once."),
              ("Also on Steam", "Bought Diablo IV on Steam instead? MacGames has a Steam version of this game too.")]),
    "diablo2-resurrected": dict(BATTLENET, slug="diablo-ii-resurrected", also="D2R", macos="26.5",
        lead="MacGames runs Diablo II: Resurrected on Apple silicon Macs. It sets up Battle.net in a Windows environment and turns the game's DirectX into Metal.",
        where="Battle.net, shared with Diablo IV",
        does=[D3DMETAL,
              ("A Battle.net that works", "The Battle.net app draws through DXMT, and MacGames brings its window back when it hides."),
              ("One Battle.net for Blizzard games", "Diablo II: Resurrected and Diablo IV share one Battle.net, so you sign in once."),
              ("A clean uninstall", "Uninstall in MacGames runs Blizzard's own uninstaller for the game.")]),
    "rdr2": dict(STEAM, slug="red-dead-redemption-2", also="RDR2", steps_install=ROCKSTAR_STEPS,
        lead="MacGames runs Red Dead Redemption 2 on Apple silicon Macs. It sets up Steam and the Rockstar Games Launcher, and turns the game's DirectX 12 into Metal.",
        where="Steam and the Rockstar Games Launcher",
        does=[("DirectX 12 through Metal", "Apple's D3DMetal turns the game's DirectX 12 calls into Metal."),
              ("A Rockstar Games Launcher that works", "The launcher draws through Wine's own renderer, while the game uses D3DMetal."),
              ("One Rockstar setup", "Red Dead Redemption 2 and GTA San Andreas share one Steam and one Rockstar Games Launcher.")]),
    "san-andreas-de": dict(STEAM, slug="gta-san-andreas-definitive-edition", also="GTA SA", short="GTA San Andreas Definitive Edition", steps_install=ROCKSTAR_STEPS,
        lead="MacGames runs GTA San Andreas: The Definitive Edition on Apple silicon Macs. It sets up Steam and the Rockstar Games Launcher, and turns the game's DirectX into Metal.",
        where="Steam and the Rockstar Games Launcher",
        does=[D3DMETAL,
              ("A Rockstar Games Launcher that works", "The launcher draws through Wine's own renderer, while the game uses D3DMetal."),
              ("One Rockstar setup", "GTA San Andreas and Red Dead Redemption 2 share one Steam and one Rockstar Games Launcher.")]),
    "gta5-enhanced": dict(STEAM, slug="gta-v-enhanced", also="GTA 5", short="GTA V Enhanced", steps_install=ROCKSTAR_STEPS,
        lead="MacGames runs Grand Theft Auto V Enhanced on Apple silicon Macs in story mode. It uses a newer Wine with Apple's D3DMetal 4.0, and answers the game's driver warning for you.",
        where="Steam and the Rockstar Games Launcher, in an environment of its own",
        online="GTA V starts without BattlEye, so story mode works and GTA Online does not.",
        does=[("A newer engine", "GTA V gets Wine 11.13 with Apple's D3DMetal 4.0, in an environment of its own."),
              ("The driver warning is answered", "The game asks for an AMD driver that cannot exist under Apple's graphics layer. MacGames closes that warning for you."),
              ("Story mode", "The game starts without BattlEye, so story mode works."),
              ("A Rockstar Games Launcher that works", "The launcher draws through Wine's own renderer, while the game uses D3DMetal.")]),
}

STORE_LINKS = {
    "overwatch": "https://overwatch.blizzard.com/",
    "diablo4-battlenet": "https://diablo4.blizzard.com/",
    "diablo2-resurrected": "https://diablo2.blizzard.com/",
}


class Covers(HTMLParser):
    """Collects each cover button's data and the cover art inside it."""
    def __init__(self):
        super().__init__()
        self.games, self.current = [], None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "button" and "cover-btn" in (attrs.get("class") or "").split():
            self.current = {k[5:]: v for k, v in attrs.items() if k.startswith("data-")}
            self.games.append(self.current)
        elif tag == "img" and self.current is not None and "cover" not in self.current:
            self.current["cover"] = attrs["src"]

    def handle_endtag(self, tag):
        if tag == "button":
            self.current = None


def e(text):
    return html.escape(text, quote=True)


def page_url(game):
    return f"{SITE}games/{GAMES[game['id']]['slug']}/"


def header(home):
    return f"""  <header class="site-header">
    <div class="wrap bar">
      <a class="brand" href="{home}">
        <img src="{home}assets/img/icon-64.png" width="30" height="30" alt="">
        MacGames
      </a>
      <nav class="nav" aria-label="Sections">
        <a href="{home}#games">Games</a>
        <a href="{home}#how">How it works</a>
        <a href="{home}#install">Install</a>
        <a href="{home}#source">Open source</a>
      </nav>
      <div class="header-cta">
        <a class="gh" href="{REPO}" aria-label="MacGames on GitHub" title="GitHub">
          {GITHUB_ICON}
        </a>
        <a class="btn btn-primary btn-small" href="{RELEASES}" data-download>Download</a>
      </div>
    </div>
  </header>"""


def game_links(games, home):
    items = "\n".join(f'          <li><a href="{home}games/{GAMES[g["id"]]["slug"]}/">{e(name_of(g))} on Mac</a></li>' for g in games)
    return f"""<nav class="footer-games" aria-label="Games">
        <p class="footer-head">Games on Mac</p>
        <ul>
{items}
        </ul>
      </nav>"""


def footer(games, home):
    return f"""  <footer class="site-footer">
    <div class="wrap">
      <div class="footer-top">
        <a class="brand" href="{home}"><img src="{home}assets/img/icon-64.png" width="26" height="26" alt="">MacGames</a>
        <nav aria-label="Project">
          <a href="{REPO}">GitHub</a>
          <a href="{REPO}/releases">Releases</a>
          <a href="{REPO}/blob/main/CHANGELOG.md">Changelog</a>
          <a href="{REPO}/blob/main/LICENSE">License</a>
        </nav>
      </div>
      <!-- game-links -->{game_links(games, home)}<!-- /game-links -->
      <p>MacGames is not affiliated with Valve, Blizzard, Rockstar Games, Microsoft or Apple. Game names and artwork belong to their owners.</p>
    </div>
  </footer>"""


def name_of(game):
    return GAMES[game["id"]].get("page_name", game["title"])


def play_step(game, words):
    if words["store"] == "Battle.net":
        return "Press Play. MacGames starts Battle.net, and Battle.net starts the game." if game["id"] == "overwatch" \
            else "Press Play. Battle.net opens. Choose Play there, and the game starts with its renderer and its fixes."
    return "Press Play. The game starts with its renderer, its fixes and your settings."


def questions(game, words):
    name, macos = words.get("game", name_of(game)), words.get("macos", "26")
    own = (f"No. {name} is free to play. You sign in to your own Battle.net account." if words.get("free")
           else f"No. You sign in to your own {words['account']} account and install the copy you own. MacGames never includes or downloads games itself.")
    test = ("Yes. It ran on an Apple silicon Mac in MacGames. Tell us how it runs on yours."
            if words.get("tested") else
            "Not yet. Its recipe is complete, but nobody has tested it in MacGames so far. Your test report helps it reach Tested.")
    online = words.get("online", "Online play with anti-cheat is at your own risk.")
    return [
        (f"Do I need to buy {name} again?", own),
        ("Which Macs can run it?", f"A Mac with Apple silicon (M1 or later) and macOS {macos} or later, with Rosetta 2. MacGames tells you how to install Rosetta 2 if it is missing. Frame rates depend on your Mac."),
        ("Has it been tested?", test),
        ("Can I play online?", online),
        ("Is MacGames free?", "Yes. MacGames is free and open source under the PolyForm Noncommercial license. Nobody can sell it."),
    ]


def game_page(game, games):
    words = GAMES[game["id"]]
    name, url, home = name_of(game), page_url(game), "../../"
    plain = words.get("game", name)  # the game itself, where the page name would repeat the store
    also = f" ({words['also']})" if words.get("also") else ""
    title = f"Play {words.get('short', name)} on Mac (Apple silicon) | MacGames"
    if len(title) > 62:
        title = title.replace(" (Apple silicon)", "")
    # Search results show about 155 characters, so the game and the app come first.
    rest = words.get("meta") or words["lead"].split(". ", 1)[1]
    description = f"Play {name} on your Apple silicon Mac with MacGames, a free app. {rest}"
    tested = words.get("tested")
    status = f'<p class="spot-status tested"><i class="dot"></i>{e(tested)}</p>' if tested \
        else '<p class="spot-status"><i class="dot"></i>Recipe ready, not tested yet</p>'
    store = STORE_LINKS.get(game["id"], f"https://store.steampowered.com/app/{game['hero'].split('/apps/')[1].split('/')[0]}/")
    does = "\n".join(f"            <li><h3>{e(h)}</h3><p>{e(p)}</p></li>" for h, p in words["does"])
    install = words.get("steps_install", "{store} opens. Sign in with your own account, then install {name} and keep the default folder.")
    install = install.format(name=plain, store=words["store"])
    faq = "\n".join(f"            <div><h3>{e(q)}</h3><p>{e(a)}</p></div>" for q, a in questions(game, words))
    others = [g for g in games if g["id"] != game["id"]]
    covers = "\n".join(
        f'          <li><a class="cover-btn" style="--accent:{g["accent"]}" href="{home}games/{GAMES[g["id"]]["slug"]}/">'
        f'<span class="cover-art"><img src="{e(g["cover"])}" alt="" width="300" height="450" loading="lazy"><span class="glare"></span></span>'
        f'<span class="cover-name">{e(name_of(g))}</span></a></li>' for g in others)
    credit = f"\n          <p class=\"fineprint\">{words['credit']}</p>" if words.get("credit") else ""
    ld = {"@context": "https://schema.org", "@type": "BreadcrumbList", "itemListElement": [
        {"@type": "ListItem", "position": 1, "name": "MacGames", "item": SITE},
        {"@type": "ListItem", "position": 2, "name": f"{name} on Mac", "item": url}]}
    return f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>{e(title)}</title>
  <meta name="description" content="{e(description)}">
  <link rel="canonical" href="{url}">
  <meta name="theme-color" content="#141A33">
  <link rel="icon" href="{home}assets/img/favicon-32.png" sizes="32x32">
  <link rel="apple-touch-icon" href="{home}assets/img/apple-touch-icon.png">
  <link rel="stylesheet" href="{home}{STYLE}">
  <script>document.documentElement.classList.add("js")</script>
  <meta property="og:type" content="website">
  <meta property="og:site_name" content="MacGames">
  <meta property="og:title" content="{e(name)} on Mac with MacGames">
  <meta property="og:description" content="{e(words['lead'])}">
  <meta property="og:url" content="{url}">
  <meta property="og:image" content="{SITE}assets/img/og-image.jpg">
  <meta name="twitter:card" content="summary_large_image">
  <script type="application/ld+json">{json.dumps(ld)}</script>
</head>
<body>
  <div class="ambient" aria-hidden="true"><span></span><span></span><span></span></div>

{header(home)}

  <main id="top">
    <section class="game-hero">
      <div class="wrap">
        <nav class="crumbs" aria-label="Breadcrumb"><a href="{home}">MacGames</a><a href="{home}#games">Games</a><span aria-current="page">{e(name)}</span></nav>
        <div class="game-stage" style="--accent:{game['accent']}; --focus:{game['focus']}">
          <img class="game-art" src="{e(game['hero'])}" alt="" fetchpriority="high">
          <div class="game-intro">
            <h1 class="game-title">{e(name)} on Mac</h1>
            <p class="lead">{e(words['lead'])}</p>
            <p class="spot-meta"><span>{e(words['where'])}</span><span>{e(game['renderer'])}</span></p>
            {status}
            <div class="hero-actions">
              <a class="btn btn-primary" href="{RELEASES}" data-download>
                <svg width="14" height="16" viewBox="0 0 14 16" aria-hidden="true"><path d="M1 1.5v13l12-6.5z" fill="currentColor"/></svg>
                Download MacGames
              </a>
              <a class="btn btn-ghost" href="{home}#games">All games</a>
            </div>
          </div>
        </div>
      </div>
    </section>

    <section class="section">
      <div class="wrap">
        <div class="section-head">
          <h2>What MacGames does for it.</h2>
          <p>{e(plain)}{e(also)} is a Windows game. MacGames brings the parts it needs to run on a Mac, and sets them up for you.</p>
        </div>
        <div class="game-split">
          <ul class="loadout pair">
{does}
          </ul>
          <dl class="needs glass">
            <div><dt>Store</dt><dd>{e(words['where'])}. <a href="{store}">{e(plain)} on {e(words['store'])}</a></dd></div>
            <div><dt>Graphics</dt><dd>{e(game['renderer'])}</dd></div>
            <div><dt>Status</dt><dd>{e(tested or "Recipe ready, not tested yet")}</dd></div>
            <div><dt>Mac</dt><dd>Apple silicon, M1 or later</dd></div>
            <div><dt>macOS</dt><dd>{words.get('macos', '26')} or later, with Rosetta 2</dd></div>
          </dl>
        </div>{credit}
      </div>
    </section>

    <section class="section">
      <div class="wrap split game-help">
        <div>
          <div class="section-head">
            <h2>From Set up to Play.</h2>
          </div>
          <ol class="steps">
            <li>
              <h3>Set up</h3>
              <p>Download MacGames, choose {e(name)} and press Set up. MacGames checks your Mac and makes a Windows environment for the game.</p>
            </li>
            <li>
              <h3>Install</h3>
              <p>{e(install)}</p>
            </li>
            <li>
              <h3>Play</h3>
              <p>{e(play_step(game, words))}</p>
            </li>
          </ol>
        </div>
        <div>
          <div class="section-head">
            <h2>Questions.</h2>
          </div>
          <div class="faq glass">
{faq}
          </div>
        </div>
      </div>
    </section>

    <section class="section">
      <div class="wrap">
        <div class="section-head">
          <h2>More games on Mac.</h2>
          <p>Each one comes with its own recipe.</p>
        </div>
        <ul class="covers linked">
{covers}
        </ul>
        <p class="fineprint">You need to own each game. Game art loads from Steam's store and belongs to each game's publisher.</p>
      </div>
    </section>

    <section class="cta-band">
      <div class="wrap">
        <h2 class="marquee small">Press Play.</h2>
        <p>{e(plain)}, on the Mac you already have.</p>
        <a class="btn btn-primary" href="{RELEASES}" data-download>
          <svg width="14" height="16" viewBox="0 0 14 16" aria-hidden="true"><path d="M1 1.5v13l12-6.5z" fill="currentColor"/></svg>
          Download for Mac
        </a>
      </div>
    </section>
  </main>

{footer(games, home)}

  <script src="{home}{SCRIPT}" defer></script>
</body>
</html>
"""


def sitemap(urls):
    rows = "\n".join(f"  <url><loc>{u}</loc><lastmod>{d}</lastmod></url>" for u, d in urls)
    return f"""<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
{rows}
</urlset>
"""


def main():
    index = DOCS / "index.html"
    source = index.read_text()
    global GITHUB_ICON
    GITHUB_ICON = re.search(r'<svg width="22".*?</svg>', source).group(0)
    parser = Covers()
    parser.feed(source)
    games = parser.games
    missing = {g["id"] for g in games} ^ set(GAMES)
    if missing:
        raise SystemExit(f"covers and GAMES differ: {sorted(missing)}")

    # Old dates stay for pages that did not change.
    old_map = DOCS / "sitemap.xml"
    dates = dict(re.findall(r"<loc>(.*?)</loc><lastmod>(.*?)</lastmod>", old_map.read_text())) if old_map.exists() else {}
    today = datetime.date.today().isoformat()

    # The home page: each cover names its page, and the footer lists every game.
    updated = re.sub(r' data-page="[^"]*"', "", source)
    updated = re.sub(r'(<button class="cover-btn"[^>]*? data-id="([^"]+)")',
                     lambda m: f'{m.group(1)} data-page="games/{GAMES[m.group(2)]["slug"]}/"', updated)
    updated = re.sub(r"<!-- game-links -->.*?<!-- /game-links -->",
                     lambda m: f"<!-- game-links -->{game_links(games, '')}<!-- /game-links -->", updated, flags=re.S)
    urls = [(SITE, today if updated != source else dates.get(SITE, today))]
    index.write_text(updated)

    for game in games:
        path = DOCS / "games" / GAMES[game["id"]]["slug"] / "index.html"
        text = game_page(game, games)
        changed = not path.exists() or path.read_text() != text
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text)
        url = page_url(game)
        urls.append((url, today if changed else dates.get(url, today)))

    old_map.write_text(sitemap(urls))
    print(f"wrote {len(games)} game pages and sitemap.xml with {len(urls)} pages")


if __name__ == "__main__":
    main()
