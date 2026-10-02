# Dot Glass marketplace review

Review candidate, not an approved marketplace release. Based on upstream commit 11d38623d7d30071a74003042ab0aed06ff61056.

## Boundaries checked

- Independent `dot-glass` identity; personal build is `dot-glass-personal`. No Codex Tracker imports, helper or data source.
- Only widget.json, listed Swift files and approved preview.png in Widgets/DotGlass.
- Metadata matches provider; author appleforever11. Both orientations render a centered ring at compact and extended sizes.
- Uses host WidgetMetrics; dock root has no frame. Host owns panel creation; no custom NSWindow/NSPanel.
- Plugin owns an @Observable connection; views use @Bindable. No singleton ObservableObject.
- Theme read via WidgetDefaults. Appearance customization belongs to host settingsSchema, not custom settings writes.
- Runtime preferences use dot-glass.*. No migration code, app config writes, file installers, subprocesses, private API, global event monitoring or updater.
- Standard WKWebView persistent data store manages sign-in. Widget does not read cookies, keychain, credentials or bearer tokens.
- Chat bridge uses rendered page elements and existing Send/Start call controls, with origin, room, duplicate-send and acknowledgment guards. No private network endpoint calls.
- Audio meter uses standard inbound WebRTC getStats. No recording, outbound audio inspection or synthetic speech. Microphone request is gated to a user-started call and the top-level ChatGPT origin.
- Native visible-panel TimelineView drives polling; no long-lived JavaScript interval. Ring respects Reduce Motion and visibility.
- Semantic panel fonts. English labels only.
- Approved artwork: opaque sRGB PNG, 1080x608, 757254 bytes; no text or UI chrome. Separate promotional hero is not in the widget folder.

## Maintainer review questions / remaining validation

The embedded authenticated ChatGPT web session and rendered-page adapter are a new integration for this submission. Passing lint does not establish that the maintainer accepts this approach. Explicitly disclose WebKit's own persistent website storage and the native/JavaScript bridge; do not hide these behind a claim of read-only behavior.

Real Dot messages and bidirectional voice were user-verified in the original personal prototype. Marketplace source now has different state ownership and polling. Fresh sign-in, message send/reply, call start/voice/end, close/reopen and theme change still require a live authenticated DockDoor test of this exact candidate. No claim of marketplace approval or release should precede that test.

ChatGPT account access to Dots and host microphone permission are required. This is a third-party UI integration, not an official OpenAI API or endorsement; site changes may require adapter updates. Voice calls are with the AI Dot, not telephone/PSTN calls.

## Review package

Source repo: https://github.com/appleforever11/DotGlass-Marketplace
Personal source/feed: https://github.com/appleforever11/DotGlass-Private
No upstream PR or marketplace deployment has been sent. Actions are disabled on the review repository to prevent inherited deployment automation.

## Prior maintainer decisions consulted

- PR #20 review: no writes to another application's config, no background-agent workaround, never reuse Tracker's ID for a new product, and no auxiliary files in a widget folder. https://github.com/ejbills/dockdoorpro-widgets/pull/20
- PR #21 maintainer follow-up: use native host settings instead of panel writes; report absent data honestly. https://github.com/ejbills/dockdoorpro-widgets/pull/21
- Current CONTRIBUTING.md and scripts/widget_rules.py are the authority for this candidate. Lint passing is explicitly not developer approval.

## Latest local checks

Universal build passed, current upstream validator passed all 11 folders, URL/origin policy test passed, and all three adapter tests passed (rendered send/acknowledgment, origin rejection, inbound-only voice meter). Native review preview inspected on the conversation and voice-tour screens. Screenshots use clearly labeled example messages, not a live call and not the user's personal conversation.

The personal Sparkle companion reached the published empty feed and displayed “You're up to date.” This verifies feed loading only. No full update/install cycle, Developer ID notarization or signed production archive has been completed.
