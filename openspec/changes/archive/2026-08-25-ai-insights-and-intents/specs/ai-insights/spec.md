## ADDED Requirements

### Requirement: Read-Only Metric App Intents
The app SHALL expose read-only monitoring intents through App Intents, available in both distribution builds, so users can query metrics from Shortcuts, Spotlight, and Siri automations.

#### Scenario: Query a single metric from Shortcuts
- **WHEN** the user runs the "Get Current Metric" intent with module CPU and metric utilization
- **THEN** the intent returns the latest sampled value with unit and sample timestamp
- **AND** no extra sampling load is triggered beyond reading the latest stored frame

#### Scenario: System snapshot for automation conditions
- **WHEN** the user builds an automation like "when CPU utilization is greater than 80%, notify me"
- **THEN** the "Get System Snapshot" intent provides all module summaries so the condition can evaluate
- **AND** the automation runs without opening the app window

#### Scenario: Entities follow user-enabled modules
- **WHEN** the user has disabled a module in settings
- **THEN** that module and its metrics are not offered as selectable entities in intents

#### Scenario: No control intents
- **WHEN** reviewing the registered intents
- **THEN** none of them mutate app settings or system state
- **AND** write/control capabilities are never exposed as public intents

### Requirement: On-Device AI Insight Summary
The app SHALL provide an optional AI diagnostic summary generated entirely on-device via Foundation Models, gated by availability, available in both distribution builds.

#### Scenario: Apple Intelligence unavailable
- **WHEN** the device does not support Foundation Models, or the user has not enabled Apple Intelligence, or the region restricts it
- **THEN** the AI insight entry is hidden entirely in panel and settings
- **AND** no dead toggle is shown

#### Scenario: Generating a diagnostic summary
- **WHEN** the user enables the AI insight setting and requests a summary
- **THEN** the app assembles recent metric snapshots, top processes, and recent events into prompt context
- **AND** requests a one-to-two sentence explanation from an on-device LanguageModelSession
- **AND** displays the result with a generation timestamp and an "on-device generated" label

#### Scenario: Generation failure or timeout
- **WHEN** the model fails to respond within the timeout
- **THEN** the card silently falls back to plain data display
- **AND** no error dialog interrupts the panel

#### Scenario: Opt-in only
- **WHEN** the AI insight setting is off (default)
- **THEN** no model session is created and no prompt is assembled

### Requirement: Local-Only Data Guarantee
All AI insight processing SHALL remain on-device with no telemetry or metric data transmitted off the machine.

#### Scenario: Network isolation
- **WHEN** an AI insight summary is generated
- **THEN** the app makes no network requests as part of the generation flow
