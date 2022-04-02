const { BigNumber } = require("ethers");
const { ethers } = require("hardhat");

module.exports = async function ({ getNamedAccounts, deployments }) {
  const { deploy, execute } = deployments;
  const { deployer } = await getNamedAccounts();

  const chainId = await getChainId();
  const ERC20ABI = [
    {
      "anonymous": false,
      "inputs": [
        {
          "indexed": true,
          "internalType": "address",
          "name": "owner",
          "type": "address"
        },
        {
          "indexed": true,
          "internalType": "address",
          "name": "spender",
          "type": "address"
        },
        {
          "indexed": false,
          "internalType": "uint256",
          "name": "value",
          "type": "uint256"
        }
      ],
      "name": "Approval",
      "type": "event"
    },
    {
      "anonymous": false,
      "inputs": [
        {
          "indexed": true,
          "internalType": "address",
          "name": "from",
          "type": "address"
        },
        {
          "indexed": true,
          "internalType": "address",
          "name": "to",
          "type": "address"
        },
        {
          "indexed": false,
          "internalType": "uint256",
          "name": "value",
          "type": "uint256"
        }
      ],
      "name": "Transfer",
      "type": "event"
    },
    {
      "inputs": [
        {
          "internalType": "address",
          "name": "owner",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "spender",
          "type": "address"
        }
      ],
      "name": "allowance",
      "outputs": [
        {
          "internalType": "uint256",
          "name": "",
          "type": "uint256"
        }
      ],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [
        {
          "internalType": "address",
          "name": "spender",
          "type": "address"
        },
        {
          "internalType": "uint256",
          "name": "amount",
          "type": "uint256"
        }
      ],
      "name": "approve",
      "outputs": [
        {
          "internalType": "bool",
          "name": "",
          "type": "bool"
        }
      ],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [
        {
          "internalType": "address",
          "name": "account",
          "type": "address"
        }
      ],
      "name": "balanceOf",
      "outputs": [
        {
          "internalType": "uint256",
          "name": "",
          "type": "uint256"
        }
      ],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [],
      "name": "totalSupply",
      "outputs": [
        {
          "internalType": "uint256",
          "name": "",
          "type": "uint256"
        }
      ],
      "stateMutability": "view",
      "type": "function"
    },
    {
      "inputs": [
        {
          "internalType": "address",
          "name": "recipient",
          "type": "address"
        },
        {
          "internalType": "uint256",
          "name": "amount",
          "type": "uint256"
        }
      ],
      "name": "transfer",
      "outputs": [
        {
          "internalType": "bool",
          "name": "",
          "type": "bool"
        }
      ],
      "stateMutability": "nonpayable",
      "type": "function"
    },
    {
      "inputs": [
        {
          "internalType": "address",
          "name": "sender",
          "type": "address"
        },
        {
          "internalType": "address",
          "name": "recipient",
          "type": "address"
        },
        {
          "internalType": "uint256",
          "name": "amount",
          "type": "uint256"
        }
      ],
      "name": "transferFrom",
      "outputs": [
        {
          "internalType": "bool",
          "name": "",
          "type": "bool"
        }
      ],
      "stateMutability": "nonpayable",
      "type": "function"
    }
  ];

  let wethAddress, routerAddress, factoryAddress;
  if (chainId == 4) {
    // rinkeby contract addresses
    wethAddress = ethers.utils.getAddress(
      "0xc778417e063141139fce010982780140aa0cd5ab"
    ); // wrapped ETH ethers.utils.getAddress
    routerAddress = ethers.utils.getAddress(
      "0x7E2528476b14507f003aE9D123334977F5Ad7B14"
    );
    factoryAddress = ethers.utils.getAddress(
      "0x86f83be9770894d8e46301b12E88e14AdC6cdb5F"
    );
  } else if (chainId == 4690) {
    // iotex testnet
    wethAddress = ethers.utils.getAddress(
      "0xff5fae9fe685b90841275e32c348dc4426190db0"
    );
    routerAddress = ethers.utils.getAddress(
      "0xF0CF2cDbED5836C3Aa3f68649e359422991743Fd"
    );
    factoryAddress = ethers.utils.getAddress(
      "0xda257cBe968202Dea212bBB65aB49f174Da58b9D"
    );
  }
  const machineFiNFT = process.env.MACHINE_FI_NFT;
  const ve = process.env.VE;
  const tokenAddress = process.env.TOKEN;
  const amount= process.env.AMOUNT;

  const event = await deploy("LaunchEventPICO", {
    from: deployer,
    args: [
      factoryAddress,
      wethAddress,
      ve,
      machineFiNFT,
      60 * 60 * 2,
      60 * 60 * 1,
      60 * 60 * 1
    ],
    log: true,
  });

  const token = await ethers.getContractAt(ERC20ABI, tokenAddress);
  await token.transfer(event.address, BigNumber.from(amount));

  await execute("LaunchEventPICO", {
    from: deployer,
    log: true,
  }, "initialize",
    deployer, // issuer
    (await ethers.provider.getBlock()).timestamp + 60, // auctionStart,
    tokenAddress,  // token,
    ethers.utils.parseEther("0.05"), // _tokenIncentivesPercent,
    ethers.utils.parseEther("1"), // floorPrice,
    ethers.utils.parseEther("0.5"), // maxWithdrawPenalty,
    ethers.utils.parseEther("0.4"), // fixedWithdrawPenalty,
    ethers.utils.parseEther("10"),  // maxAllocation,
    60 * 60 * 1, // userTimelock,
    60 * 60 * 2, // issuerTimelock
  );
};

module.exports.tags = ["LaunchEventPICO"];
