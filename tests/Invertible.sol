import 'base64-sol/base64.sol';

contract InvertibleBroken {
	address public admin;
	uint public counter;

	function inc() public returns (uint) {
		require(msg.sender == admin);
		return ++counter;
	}

	function dec() public returns (uint) {
		require(msg.sender == admin);
		return --counter;
	}
}
