pragma solidity ^0.8.0;

import "solmate/tokens/ERC20.sol";

contract DevTokenA is ERC20 {

	constructor() 
    	ERC20("Development Token A", "DTA", 18) 
    	public
    {
        _mint(msg.sender, 1000000000 * 10**18);
    }
}