### Changed

- **Hybrid Copilot skill loading (#549).** Role-core skills preload through
  agent frontmatter; conditional runbooks load through the native `skill`
  tool. The validator checks active targets, invocation flags, required
  preloads and matching tool grants, excluding project-managed regions.
  Curation recognizes frontmatter preloads. Coordinator TDD, Git and notebook
  depth is conditional; global Git instructions retain the shared boundaries.
- **Context budgets include preloaded skill bodies and declared conditional
  skill inventory (#549).** Conditional skill bodies are reported separately
  from instruction/catalogue costs, with per-agent declared upper bounds.
  Optional AF/project individual and unique-aggregate skill ceilings enforce
  when set; unset ceilings say `UNBUDGETED`. Shared skills count once in the
  inventory. Owner-approved ceilings retain roughly 20% headroom over the
  measured optimized payload: agent/preload baseline 18,600, individual
  conditional skill 7,150, unique conditional inventory 49,400 tokens.
  Static bounds are not invocation frequency or billed usage; Copilot-native
  skill usage reporting remains #556.
