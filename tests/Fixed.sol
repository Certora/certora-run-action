import 'base64-sol/base64.sol';

contract Fixed {
	address public admin;
	uint public counter;

	function inc() public returns (uint) {
		require(msg.sender == admin);
		require(counter < 1000);
		return ++counter;
	}

	function dec() public returns (uint) {
		require(msg.sender == admin);
		require(counter > 0);
		return --counter;
	}
}
