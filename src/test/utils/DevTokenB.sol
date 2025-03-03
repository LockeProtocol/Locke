pragma solidity ^0.8.0;

import "solmate/tokens/ERC20.sol";

contract DevTokenB is ERC20 {

	constructor() 
    	ERC20("Development Token B", "DTB", 18) 
    	public
    {
        _mint(msg.sender, 1000000000 * 10**18);
    }
}