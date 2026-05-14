//! Apply a sequence of Actions to a TreasuryState, producing a post-state. Used by the engine
//! to evaluate hard constraints against the simulated outcome.

use crate::types::{Action, TreasuryState};

pub fn apply_actions(state: TreasuryState, _actions: &[Action]) -> TreasuryState {
    // TODO(mulerun):
    //   for action in actions:
    //     match action.kind:
    //       TRANSFER: subtract amount from asset balance
    //       SWAP:      decode params for tokenOut; subtract from in, add to out (at oracle px)
    //       SUPPLY:    move from underlying to aToken position
    //       WITHDRAW:  reverse of SUPPLY
    //       BUY_RWA:   subtract USDC, add RWA token
    //       SELL_RWA:  reverse
    //       BUY_PT / SELL_PT: similar swap semantics
    //   recompute total_nav_usdc
    //   recompute state_hash
    state
}
