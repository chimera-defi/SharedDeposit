pragma solidity 0.8.20;

abstract contract OnlyOnce {
    error AlreadyCalled();

    uint8 private _called; // trace fn calls and state. e.g. called[0] returns the no. of times the tracing fn has been called
    function _onlyOnce() internal {
      // can only be called once.
      if (_called > 0) {
        revert AlreadyCalled();
      }
      _called = 1;
    }
}
