## ADDED Requirements

### Requirement: Process sampling executes on a single serial queue
The system SHALL execute all TOP-process sampling (memory, CPU, disk, network) on a single serial dispatch queue, so that the process-level snapshot state used for delta computation is never mutated concurrently.

#### Scenario: Concurrent sampling requests are serialized
- **WHEN** multiple sampling requests (timer tick, newly expanded module, baseline prewarm) are dispatched to the process sample queue
- **THEN** they execute one at a time, and the global disk/network snapshot dictionaries are read and mutated without data races

#### Scenario: Comments describe the serial execution model
- **WHEN** a developer reads the sampling dispatch code
- **THEN** the comments state that execution is serial and that serialization is a correctness prerequisite for the unlocked snapshot state, rather than claiming parallel execution

### Requirement: Network throughput ignores counter resets
The network sampler SHALL clamp per-interval upload and download rates to non-negative values, so that interface counter resets or primary-interface changes do not produce spurious throughput spikes.

#### Scenario: Cumulative byte counter decreases between samples
- **WHEN** the current cumulative input or output byte count is lower than the previous sample
- **THEN** the computed rate for that direction is zero for the interval, rather than a wrapped large value

### Requirement: SMC float parsing tolerates unaligned bytes
The SMC reader SHALL parse `flt`-typed values from the raw byte buffer without assuming 4-byte memory alignment.

#### Scenario: Reading a float-typed SMC key
- **WHEN** the SMC returns a `flt ` typed value in the raw byte buffer
- **THEN** the reader loads the float with an unaligned load and returns the correct temperature value
