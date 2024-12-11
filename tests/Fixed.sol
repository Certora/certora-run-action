contract Fixed {
	address public admin;
	uint public counter;

	function inc() public returns (uint) {
		require(msg.sender == admin);
		require(counter < uint256(-1));
		return ++counter;
	}

	function dec() public returns (uint) {
		require(msg.sender == admin);
		require(counter > 0);
		return --counter;
	}
}
