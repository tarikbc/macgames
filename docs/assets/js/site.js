// MacGames site behavior. Everything here only adds to a page that already reads fine
// without JavaScript. With reduced motion, nothing moves on its own.
(() => {
  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Download buttons point at the newest release's disk image and show its version.
  (async () => {
    try {
      const response = await fetch("https://api.github.com/repos/tarikbc/macgames/releases/latest",
                                   { headers: { Accept: "application/vnd.github+json" } });
      if (!response.ok) return;
      const release = await response.json();
      const dmg = (release.assets || []).find((asset) => asset.name.endsWith(".dmg"));
      if (dmg) document.querySelectorAll("[data-download]").forEach((link) => { link.href = dmg.browser_download_url; });
      const version = (release.tag_name || "").replace(/^v/, "");
      if (version) document.querySelectorAll("[data-version]").forEach((el) => { el.textContent = `Version ${version}.`; });
    } catch (_) {
      // The release page link stays.
    }
  })();

  // The header turns solid once the page leaves the hero.
  const header = document.querySelector(".site-header");
  const onScroll = () => header.classList.toggle("scrolled", window.scrollY > 24);
  onScroll();
  window.addEventListener("scroll", onScroll, { passive: true });

  // Title-screen letters, so each one can set in on its own beat.
  document.querySelectorAll(".marquee").forEach((title) => {
    const text = title.textContent;
    title.setAttribute("aria-label", text);
    title.textContent = "";
    [...text].forEach((ch, i) => {
      const span = document.createElement("span");
      span.className = "ch";
      span.setAttribute("aria-hidden", "true");
      span.style.setProperty("--i", i);
      span.textContent = ch === " " ? " " : ch;
      title.append(span);
    });
  });

  // Parts that animate once when they scroll in.
  document.querySelectorAll(".section-head h2, .section-head p").forEach((el) => el.setAttribute("data-reveal", ""));
  document.querySelectorAll(".covers li").forEach((li, i) => li.style.setProperty("--i", i));
  const loadout = document.querySelector(".loadout");
  if (loadout) {
    const tops = [...new Set([...loadout.children].map((li) => li.offsetTop))].sort((a, b) => a - b);
    [...loadout.children].forEach((li) => li.style.setProperty("--row", tops.indexOf(li.offsetTop)));
  }
  // Headings start fully clipped, which an observer counts as not on screen, so their block is watched.
  const watched = document.querySelectorAll(".section-head, [data-lock]:not(.hero-shot), .steps li, .loadout, .covers, .installer, .cta-band");
  const reveal = (el) => {
    el.classList.add("in");
    el.querySelectorAll("[data-reveal]").forEach((child) => child.classList.add("in"));
  };
  if (reduceMotion || !("IntersectionObserver" in window)) {
    watched.forEach(reveal);
    document.querySelectorAll(".hero-shot").forEach((el) => el.classList.add("in"));
  } else {
    const observer = new IntersectionObserver((entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        reveal(entry.target);
        observer.unobserve(entry.target);
      });
    }, { rootMargin: "0px 0px -12% 0px", threshold: 0.15 });
    watched.forEach((el) => observer.observe(el));
    // The hero screenshot locks on once it has risen from the floor.
    setTimeout(() => document.querySelectorAll(".hero-shot").forEach((el) => el.classList.add("in")), 1500);
  }

  setUpGameSelect(document.querySelector("[data-select]"));

  function setUpGameSelect(root) {
    if (!root) return;
    const groups = { steam: "Steam library", battlenet: "Battle.net", rockstar: "Rockstar", own: "On their own" };
    const spotlight = root.querySelector(".spotlight");
    const stage = root.querySelector(".spot-stage");
    const progress = root.querySelector(".spot-progress");
    const covers = [...root.querySelectorAll(".cover-btn")];
    const filters = [...root.querySelectorAll(".filter")];
    let current = covers.find((c) => c.getAttribute("aria-pressed") === "true") || covers[0];
    let auto = !reduceMotion;
    stage.querySelector(".spot-art").classList.add("current");

    const visible = () => covers.filter((c) => !c.closest("li").classList.contains("out"));
    const element = (tag, className, text) => {
      const node = document.createElement(tag);
      if (className) node.className = className;
      if (text !== undefined) node.textContent = text;
      return node;
    };

    function show(cover, byUser) {
      if (byUser) stopAuto();
      if (cover === current && stage.querySelector(".spot-body")) { restartProgress(); return; }
      current = cover;
      covers.forEach((c) => c.setAttribute("aria-pressed", String(c === cover)));
      const d = cover.dataset;

      const art = element("div", "spot-art entering");
      art.style.setProperty("--focus", d.focus);
      const hero = element("img", "spot-hero");
      hero.alt = "";
      hero.src = d.hero;
      art.append(hero);
      stage.querySelectorAll(".spot-art").forEach((old) => setTimeout(() => old.remove(), 900));
      stage.querySelector(".spot-body")?.before(art);

      const body = element("div", "spot-body entering");
      body.style.setProperty("--accent", d.accent);
      if (d.logo) {
        const logo = element("img", "spot-logo");
        logo.src = d.logo;
        logo.alt = d.title;
        body.append(logo);
      } else {
        body.append(element("p", "spot-logo-text", d.title));
      }
      body.append(element("h3", "spot-title", d.title));
      const meta = element("p", "spot-meta");
      meta.append(element("span", "", groups[d.group]), element("span", "", d.renderer));
      const recipe = element("ul", "spot-recipe");
      d.recipe.split("|").forEach((line) => recipe.append(element("li", "", line)));
      const status = d.status ? element("p", "spot-status tested", d.status)
                              : element("p", "spot-status", "Recipe ready. Test it and tell us.");
      body.append(meta, recipe, status);
      stage.querySelector(".spot-body")?.remove();
      stage.append(body);

      // The next hero art loads while this one is on show.
      const next = neighbor(1);
      if (next) new Image().src = next.dataset.hero;
      restartProgress();
    }

    function neighbor(step) {
      const list = visible();
      const index = list.indexOf(current);
      return list[(index + step + list.length) % list.length];
    }

    function restartProgress() {
      progress.classList.remove("running");
      if (!auto) return;
      void progress.offsetWidth;
      progress.classList.add("running");
    }

    function stopAuto() {
      auto = false;
      progress.classList.remove("running", "paused");
      progress.classList.add("stopped");
      spotlight.setAttribute("aria-live", "polite");
    }

    // The bar's fill is the timer: when it is full, the next game comes up.
    progress.querySelector("span").addEventListener("animationend", () => { if (auto) show(neighbor(1), false); });
    spotlight.setAttribute("aria-live", auto ? "off" : "polite");

    // Auto-play waits while the pointer or focus is on the section, or while it is off screen.
    let hovering = false, focused = false, onScreen = false;
    const updatePause = () => progress.classList.toggle("paused", hovering || focused || !onScreen || document.hidden);
    root.addEventListener("pointerenter", () => { hovering = true; updatePause(); });
    root.addEventListener("pointerleave", () => { hovering = false; updatePause(); });
    root.addEventListener("focusin", () => { focused = true; updatePause(); });
    root.addEventListener("focusout", () => { focused = root.contains(document.activeElement); updatePause(); });
    document.addEventListener("visibilitychange", updatePause);
    if ("IntersectionObserver" in window) {
      new IntersectionObserver(([entry]) => { onScreen = entry.isIntersecting; updatePause(); }, { threshold: 0.35 }).observe(spotlight);
    }
    updatePause();
    restartProgress();

    covers.forEach((cover) => {
      cover.addEventListener("click", () => {
        show(cover, true);
        if (spotlight.getBoundingClientRect().top < 0) spotlight.scrollIntoView({ behavior: reduceMotion ? "auto" : "smooth", block: "start" });
      });
      if (reduceMotion) return;
      // Covers lean toward the pointer, with a glare that follows it.
      cover.addEventListener("pointermove", (event) => {
        const box = cover.getBoundingClientRect();
        const x = (event.clientX - box.left) / box.width, y = (event.clientY - box.top) / box.height;
        cover.classList.add("tilting");
        cover.style.setProperty("--ry", `${(x - 0.5) * 18}deg`);
        cover.style.setProperty("--rx", `${(0.5 - y) * 18}deg`);
        cover.style.setProperty("--mx", `${x * 100}%`);
        cover.style.setProperty("--my", `${y * 100}%`);
      });
      cover.addEventListener("pointerleave", () => {
        cover.classList.remove("tilting");
        ["--rx", "--ry", "--mx", "--my"].forEach((name) => cover.style.removeProperty(name));
      });
    });

    root.querySelectorAll(".spot-step").forEach((button) => {
      button.addEventListener("click", () => show(neighbor(Number(button.dataset.step)), true));
    });

    // Arrow keys move through the covers, like a console library.
    root.querySelector(".covers").addEventListener("keydown", (event) => {
      const list = visible();
      const index = list.indexOf(document.activeElement);
      if (index < 0) return;
      const columns = Math.max(1, Math.round(root.querySelector(".covers").clientWidth / list[0].getBoundingClientRect().width) - 1);
      const moves = { ArrowRight: 1, ArrowLeft: -1, ArrowDown: columns, ArrowUp: -columns };
      if (!(event.key in moves)) return;
      event.preventDefault();
      const target = list[Math.min(list.length - 1, Math.max(0, index + moves[event.key]))];
      target.focus();
      show(target, true);
    });

    filters.forEach((filter) => {
      filter.addEventListener("click", () => {
        const group = filter.dataset.filter;
        filters.forEach((f) => {
          f.classList.toggle("is-active", f === filter);
          f.setAttribute("aria-pressed", String(f === filter));
        });
        // FLIP: covers that stay glide to their new place; covers that join pop in.
        const before = new Map(visible().map((c) => [c, c.getBoundingClientRect()]));
        covers.forEach((c) => c.closest("li").classList.toggle("out", group !== "all" && c.dataset.group !== group));
        let joined = 0;
        visible().forEach((c) => {
          const li = c.closest("li");
          const old = before.get(c);
          li.classList.remove("entering");
          if (!old) {
            li.style.setProperty("--j", joined++);
            void li.offsetWidth;
            li.classList.add("entering");
          } else if (!reduceMotion) {
            const now = c.getBoundingClientRect();
            const dx = old.left - now.left, dy = old.top - now.top;
            if (dx || dy) li.animate([{ transform: `translate(${dx}px, ${dy}px)` }, { transform: "none" }],
                                     { duration: 450, easing: "cubic-bezier(0.2, 0.8, 0.2, 1)" });
          }
        });
        const first = visible()[0];
        if (first && !visible().includes(current)) show(first, false);
        else if (first) restartProgress();
      });
    });
  }
})();
