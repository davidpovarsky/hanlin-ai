# Migration iPad admission correction

Source commit ae21e071aba7d5fc3d2a55f39c47ee81b19278c1 adds only the two exact migration scopes to the existing iPad device-family condition. R2 incorrectly fell through to the original iPhone default for these new scopes, contrary to its reviewed fresh-iPad contract. All prior route predicates, original test methods, UI bytes, phases, deadlines and assertions remain unchanged. The whole R2 runner is recovered by reversing the single addition.

The reviewed R2 source/proof commits 54b7d81c736ccc9e4c1081296ceafc525fe506f0 and e3b07c577d6424f355a360d4b2f668645e6e3bd5 remain immutable. The earlier composed UI typecheck is unaffected by this runner-only correction; the eventual whole composed UI and actual two migration runs remain separately qualified. No control, build, Simulator or test command ran during this correction. The exact independent root review and lossless patch are retained here.
