# Native operation cancellation and cleanup

Status: in progress. Cooperative cancellation is negotiated; native Stop acceptance remains open.

Step 1 is implemented and its 13 focused guard tests pass. Step 2 now has a
required-binding stdio reader/serial-action lane and private targeted cancellation;
lane and real-pipe reader tests pass with inert event sinks. The acknowledgment
distinguishes requested cancellation from cleanup confirmation. Step 3 now records downs by delivery path and submits identity-checked releases
on scope exit, including cancellation and exceptions. Step 4 is wired into explicit host Stop with bounded notification and cleanup
grace, followed by process termination under the existing lease. Step 5 remains. The app-agent proxy is still synchronous.

The embedding host needs Stop to fence native input while preserving the
approved target identity. Existing synchronous stdio processing cannot read a
cancellation message during an operation. Killing the helper does not run Swift
cleanup and cannot prove that held input was released.

## Implementation sequence

1. Add a thread-safe, irreversible operation cancellation token. Bind it to the
   existing thread-scoped input guard and check it before each targeted, global,
   private, and Accessibility mutation. Test with inert event sinks.
2. Provide bounded transport signaling that reaches the token during execution.
   Keep ordinary calls serialized; cancellation must not execute a second action.
3. Track accepted downs by original process identity and delivery mechanism.
   Revalidate that identity before sending cleanup-only releases. Include private
   SkyLight and global pointer delivery, and retain uncertain cleanup outcomes.
4. Negotiate the stronger contract with the embedding host. Keep bounded process
   termination as fallback and retain the machine lease until confirmed exit.
5. Stage the helper and validate actual key/button release and foreground behavior
   in the built application. Unit tests cannot establish WindowServer delivery.

Preserve existing grants, default standalone behavior, profiles, and unrelated
work. Do not commit, publish, or launch a native UI as part of unit verification.
The capability describes cooperative cancellation support, not confirmed OS cleanup.
