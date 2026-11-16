export const meta = {
  name: 'look-overhaul-build',
  description: 'Parallel team builds the look overhaul (relight, studs, town, real hospital, HUD rails, unified panels, tutorial beam) in an isolated worktree',
  phases: [
    { title: 'Foundation', detail: 'Task 0: config, palette/theme tokens, world split, studs, logic + specs, stubs; commit', model: 'fable' },
    { title: 'Build', detail: 'T1-T9 in parallel, strict file ownership, no commits' },
    { title: 'Integrate', detail: 'apply cross-file requests, trace flows, part budget, lint, build, commit', model: 'fable' },
    { title: 'Review', detail: 'systems+safety+budgets and look+UX lenses', model: 'fable' },
    { title: 'Fix', detail: 'verify and fix findings, commit', model: 'fable' },
  ],
}

const WT = 'c:\\dev\\games-agents\\.worktrees\\look'
const PLAN = WT + '\\docs\\plan\\2026-11-17-look-overhaul-build-plan.md'
const COMMON = `
You work in the git worktree ${WT} (branch claude/look-overhaul). ONLY edit files under ${WT}. NEVER touch c:\\dev\\games-agents outside .worktrees\\look (the user publishes from the main checkout, which Rojo syncs live into Studio), never use Roblox Studio MCP tools (the lead playtests in Studio after the merge; ignore the plan's Studio steps for yourself, list what the lead must check instead), never push.
The game: "Cure a Creature", a live Roblox kids' creature-clinic game (Rojo project in ${WT}\\game, Luau). Read ${WT}\\game\\README.md for architecture, modules, boot order and test switches. Progression v2 is merged into this tree.
The build plan ${PLAN} is LAW: file ownership in section A, contracts in section B, numbers in section C, tasks in section D, conflicts with Progression v2 in section G. Its section F open points ship with their stated defaults (keep every such number in Config). Binding rulings (read them in ${WT}\\memory\\records): memory-20261117-001 (Joshua's look decisions), -002 (wards look full; tutorial replay in Settings), -003 (Claude's provisional defaults), -004 (creatures go blocky), memory-20261116-022 (countdowns only for FREE events). Specs: docs/research/2026-11-16-art-direction.md, -hospital-building.md, -ux-cohesion-audit.md, -tutorial-ux.md.
Kids' rules (CLAUDE.md red line 3): no timer or "only N left" on anything paid; odds always shown and true; no fail states; every motion honours Kit.reducedMotion(); text never under 18 px. Original content only (red line 2): no other game's assets, never the word "LEGO" (say "studs"), no red cross emblem. The server is authoritative; validate every remote.
Keep every existing system working: Progression v2 (roster, rebirth/branches, Agency, Market, Lift, A&E, triage), Update 1 (belt, nurses, mini-games, levels, boosts, badges, boards), the tutorial, saving.
Tooling (PowerShell, from ${WT}\\game): & "$env:USERPROFILE\\.rokit\\bin\\stylua.exe" src tests ; & "$env:USERPROFILE\\.rokit\\bin\\selene.exe" src (0 errors, 0 warnings) ; & "$env:USERPROFILE\\.rokit\\bin\\lune.exe" run tests/run (all pass) ; & "$env:USERPROFILE\\.rokit\\bin\\rojo.exe" build default.project.json -o "$env:TEMP\\look-check.rbxl".`

const REPORT = {
  type: 'object',
  properties: {
    summary: { type: 'string' },
    files: { type: 'array', items: { type: 'string' } },
    lint: { type: 'string' },
    specs: { type: 'string' },
    requests: { type: 'array', items: { type: 'string' }, description: 'Exact changes needed in files you do not own (file, where, what)' },
    concerns: { type: 'array', items: { type: 'string' } },
  },
  required: ['summary', 'files', 'lint', 'specs', 'requests', 'concerns'],
}

const FINDINGS = {
  type: 'object',
  properties: {
    findings: {
      type: 'array',
      items: {
        type: 'object',
        properties: {
          severity: { type: 'string', enum: ['critical', 'high', 'medium', 'low'] },
          file: { type: 'string' },
          line: { type: 'number' },
          title: { type: 'string' },
          detail: { type: 'string' },
          fix: { type: 'string' },
        },
        required: ['severity', 'file', 'title', 'detail', 'fix'],
      },
    },
  },
  required: ['findings'],
}

phase('Foundation')
const foundation = await agent(`${COMMON}

You are TASK 0, FOUNDATION, for the look overhaul. Everyone else builds on what you commit, so be precise.
1. Read the build plan fully (it was written while Progression v2 was still in flight: first check section A/B/G against the ACTUAL merged tree, and fix the plan text wherever the real file names, APIs or layouts differ; say so in your report).
2. Implement exactly the Task 0 scope of section D/B: Config, Types, Remotes (incl. the player-safe TutorialReplay), Palette (old keys as aliases), Theme tokens, Data/Logic modules (Tutorial, HudZones, NextEvent, Building ...) with Lune specs, the World/Parts and World/Studs helpers (Plastic + TopSurface Studs fallback until the CureStuds MaterialVariant exists), the PlotBuilder/Hud splits into the new files with stubs carrying the exact section B APIs so everything requires and boots, Main.server/Main.client wiring, PartBudget.spec, README.
3. Lint clean, all specs pass (old and new), rojo build OK, then git add + commit in the worktree ("Look overhaul foundation: tokens, world split, studs, logic, stubs"). Return the REPORT.`, { label: 'Task 0 foundation', phase: 'Foundation', schema: REPORT, model: 'fable' })
log(`Foundation: ${foundation ? foundation.summary.slice(0, 200) : 'FAILED'}`)

phase('Build')
const TASKS = [
  { id: 'T1', label: 'T1 lighting', brief: 'Lighting: DayNight relit to the art spec §4.3 for day and night (LightingStyle Soft, PrioritizeLightingQuality, ambient, grade, mid-blue atmosphere, bloom, sun rays), night lamps.' },
  { id: 'T2', label: 'T2 town world', brief: 'Town world: the studded two-tone checker lawns, voxel trees in three greens (blossom at most 1 in 6), the dark road with warm lines and slate curbs, the spawn plaza moved off the centre line, the Nurse Belt down the centre line of the road (keep the spawn and every gate clear; riders, hire taps and the sign still work), floating outlined sign text, the odds list on a navy plate, the Hall of Fame garden and the Agency/Market kiosks restyled and moved per section G.' },
  { id: 'T3', label: 'T3 hospital building', brief: 'Hospital building: the real studded building from Lv 1 to Lv 5 per the hospital design and section B6 (the Stand as a podium clinic, the tower floor per level, glass lift corner, stairs, wards that LOOK FULL: 7 beds on the ward floor, 3 usable named Bed_<n> + 4 decorative never named Bed_, sleeping stand-ins), A&E door, helipad, paw-heart logo, solid upper walls and the client cutaway. Every name Lift, LiftPanel, Patients, Levels, Stations and effects look up stays the same; floor slabs at 10.4+; straight-line reachable beds. Report measured part counts per level.' },
  { id: 'T4', label: 'T4 plot + rooms', brief: 'Plot and rooms: the dark studded plot pad with stone edging, the lean scenery (wider fence posts, one-cube bushes, annexes), rooms without lerp-to-white (plank floors, accent dado, warm upper walls), decor slots, the queue lane in mid-tones; keep the queue lane, its numbered spots, the gate and the sign clear at every level. Report part counts.' },
  { id: 'T5', label: 'T5 HUD', brief: 'HUD: the zone map of section B7: the wallet (icon + big outlined number, no pills), the top-centre Now card (warnings, tutorial, tracked goal), the top-right status column (day/night in words, one free-event countdown chip from Logic/NextEvent, visitor, boosts), the left rail (Shop, Nurses, Book, Badges, Top) and right rail (Gifts, Goals, Mail) with one shared fill and still red dots, phones 3 a side with Badges/Top under the gear More menu, the hands at bottom centre, toasts under the Now card. Check 640x360 to 1920x1080.' },
  { id: 'T6', label: 'T6 chrome + panels', brief: 'Chrome and core panels: the one Modal template (navy header, white body, tinted cards, one tab component, one text-fit helper with an 18 px floor), the button roles, then migrate Shop, BookPanel, Boards, BadgeBook, Mailbox, PlayGifts, DayReportPanel, AdminPanel and MiniGames onto it without losing any feature (mini-game auto-Perfect, Ease, Soak, Triage).' },
  { id: 'T7', label: 'T7 progression panels', brief: 'Progression panels: migrate NursePanel, AgencyPanel, MarketPanel, BranchPanel and LiftPanel onto the shared Modal (look only: their behaviour and testable blocks stay), shared confirm and odds popups, themes recolour only trim and the roof band.' },
  { id: 'T8', label: 'T8 tutorial', brief: 'Tutorial: the top-centre step card ("TUTORIAL n/N", icon, title, yellow hint, a bar that fills on success), the floor-level guide beam from the HumanoidRootPart to the target (section B9 values; re-aimed flat every frame; hides within ~6 studs; re-targets per step; survives respawn), one Highlight glow on the target, a few still ground chevrons, the guide nurse (placeholder), a celebration per step, Skip (beam stays until 3 cures) and the player-safe Replay from the gear Settings with a confirm, a final "coming up" chip for the next free event.' },
  { id: 'T9', label: 'T9 blocky creatures', brief: 'Blocky creatures (memory-20261117-004; plan section D T9): rebuild CreatureBuilder.build/buildLook so every patient and nurse is made of blocks (studs only on big upward faces via World/Studs, SmoothPlastic small parts, mid-value colours, flat block faces with glinting eyes, blush and a pixel mouth, mood swaps, a distinct ear shape per species, every species keeps its own silhouette and Bits), with the rig contract exactly unchanged (Root, Core, PoseJoint, Motor6Ds, sockets, IconAnchor, MOTION_TAG and every helper), night glow and variants working, under 40 parts; NurseBuilder fits the cap, tray and glow onto the blocky body. Look at the prototype screenshots in logs/playtests/2026-11-17-look-spike/4-*.jpg, 5-*.jpg, 6-*.jpg.' },
]
const reports = await parallel(TASKS.map(t => () => agent(`${COMMON}

You are ${t.id} for the look overhaul. The foundation is committed in the worktree; read the build plan (section A ownership, section B contracts, your section D task) first. Your task: ${t.brief}
Edit ONLY the files section A gives ${t.id} (other devs edit the rest of the worktree at the same time). If you need a change in someone else's file or the frozen layer, do NOT edit it: put the exact change in REPORT.requests. Write Lune specs for what is testable. Do NOT commit. Lint your files clean and make sure the whole tree still builds and specs pass. Return the REPORT, with concerns = what the lead must look at in Studio.`, { label: t.label, phase: 'Build', schema: REPORT })))
const ok = reports.filter(Boolean)
log(`Build done: ${ok.length}/${TASKS.length} reports`)

phase('Integrate')
const integration = await agent(`${COMMON}

You are the INTEGRATOR for the look overhaul. The build reports are below as JSON. Your job:
1. Apply every request that is still needed.
2. Cross-check section B contracts end to end: every require resolves, no cycles, remote names and payloads match on both sides, every name other systems look up in the hospital (Lift, Patients' Bed_<n>, Stations, A&E, helipad) still resolves, section G's 17 conflicts each handled.
3. Trace these flows in code: a new player's tutorial (beam, card, glow, skip, replay); a patient walking from the queue lane to an upstairs ward bed via the lift landing; the belt down the road's centre (spawn clear, hire works); a rebirth with a theme; the HUD on a 640x360 phone and a 1920x1080 desktop; a Lv 5 plot with every decor slot filled (part count must be <= 400, by spec).
4. Update README (module table, boot order, remotes, test switches, playtest checklist) and the perf note's counts.
5. Lint clean, all specs pass, rojo build OK. Commit in the worktree ("Look overhaul: parallel build integrated").
Return the REPORT (requests = anything left undone; concerns = the Studio checks for the lead).

BUILD REPORTS:
${JSON.stringify(ok, null, 1)}`, { label: 'Integrator', phase: 'Integrate', schema: REPORT, model: 'fable' })

phase('Review')
const LENSES = [
  { key: 'systems-safety-budgets', prompt: 'SYSTEMS + SAFETY + BUDGETS lens: runtime errors (nil indexing, wrong signatures, yields in wrong places, client/server split), anything Progression v2 or Update 1 relied on that the overhaul broke (lift, A&E, triage, beds, belt hire, Agency, Market, rebirth themes, mini-games, tutorial save state), the TutorialReplay remote (own save only, rate limit), part counts per level vs 400, per-frame loops (the beam re-aim, cutaway, HUD), memory/connection leaks, reduced motion.' },
  { key: 'look-ux', prompt: 'LOOK + UX lens, against the specs (art direction §4, hospital design, UX audit §3, tutorial §3/§5, rulings memory-20261117-001/-002): palette values and the no-lerp-to-white rule, studs where they belong and not where they do not, dark anchors, the HUD zone map (every piece in exactly one zone, nothing in the bottom corners, phone layout), one modal look (navy header, button roles, 18 px floor), the tutorial beam at floor height from the body to the target, wards visibly full, signs as floating outlined text, free-event countdown only, kids clarity on a phone.' },
]
const reviews = await parallel(LENSES.map(l => () => agent(`${COMMON}

Review the integrated look overhaul in the worktree (commit "Look overhaul: parallel build integrated" and its foundation). ${l.prompt}
Read the actual code; report only real, specific problems with file and line and a concrete fix. Don't edit files. Return FINDINGS.`, { label: 'review:' + l.key, phase: 'Review', schema: FINDINGS, model: 'fable' })))
const findings = reviews.filter(Boolean).flatMap(r => r.findings)
log(`Review: ${findings.length} findings (${findings.filter(f => f.severity === 'critical' || f.severity === 'high').length} critical/high)`)

phase('Fix')
const fix = findings.length === 0 ? null : await agent(`${COMMON}

You are the FIXER for the look overhaul. Verify each finding below against the code (some may be wrong or duplicates); fix every real one, keeping the contracts. Lint clean, all specs pass, rojo build OK, then commit in the worktree ("Look overhaul: review fixes"). Return the REPORT, with concerns = exactly what the lead must check live in Studio.

FINDINGS:
${JSON.stringify(findings, null, 1)}`, { label: 'Fixer', phase: 'Fix', schema: REPORT, model: 'fable' })

return { foundation, build: ok, integration, findings, fix }
