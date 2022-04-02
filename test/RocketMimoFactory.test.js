const { ethers, network } = require("hardhat");
const { expect } = require("chai");
const { advanceTime, duration } = require("./utils/time");
const { deployRocketFactory, createLaunchEvent } = require("./utils/contracts");
const { BigNumber } = require("ethers");

describe("rocket factory test", function () {
    before(async function () {
        // The wallets taking part in tests.
        this.signers = await ethers.getSigners();
        this.dev = this.signers[0];
        this.penaltyCollector = this.signers[1];
        this.issuer = this.signers[2];
        this.alice = this.signers[3];
        this.bob = this.signers[4];

        this.ERC20TokenCF = await ethers.getContractFactory("ERC20Token");
        this.ERC721TokenCF = await ethers.getContractFactory("ERC721Token");
    });

    beforeEach(async function () {
        this.AUCTOK = await this.ERC20TokenCF.deploy();
        this.machineFiNFT = await this.ERC721TokenCF.deploy();

        this.RocketFactory = await deployRocketFactory(
            this.dev,
            this.penaltyCollector,
            this.machineFiNFT.address,
        );

        const amount = ethers.utils.parseEther("105");
        await this.AUCTOK.connect(this.dev).mint(this.issuer.address, amount);
        await this.AUCTOK.connect(this.issuer).transfer(this.dev.address, amount);
        await this.AUCTOK.connect(this.dev).approve(this.RocketFactory.address, amount);
    });

    it("check user max allocation", async function () {
        const event = await createLaunchEvent(
            this.RocketFactory,
            this.issuer,
            await ethers.provider.getBlock(),
            this.AUCTOK,
        );

        const baseAllocation = await event.maxAllocation();

        expect(baseAllocation).to.equals(await event.userMaxAllocation(this.alice.address));

        await this.machineFiNFT.connect(this.alice).mint(this.alice.address, 0);
        expect(baseAllocation.mul(5)).to.equals(await event.userMaxAllocation(this.alice.address));

        await this.machineFiNFT.connect(this.alice).mint(this.alice.address, 1);
        expect(baseAllocation.mul(5)).to.equals(await event.userMaxAllocation(this.alice.address));
        
        const masterChefPointCF = await ethers.getContractFactory("MasterChefPoint");
        const chef = await masterChefPointCF.deploy();
        await chef.addUserPoints(this.alice.address, ethers.utils.parseEther("1"));
        await chef.addUserPoints(this.bob.address, ethers.utils.parseEther("99"));

        await event.connect(this.dev).setMasterChefPoint(chef.address, 100);

        expect(baseAllocation.mul(6)).to.equals(await event.userMaxAllocation(this.alice.address));
        expect(baseAllocation.mul(100)).to.equals(await event.userMaxAllocation(this.bob.address));
    });
    
    it("test deposit", async function () {
        const event = await createLaunchEvent(
            this.RocketFactory,
            this.issuer,
            await ethers.provider.getBlock(),
            this.AUCTOK,
        );

        await advanceTime(duration.seconds(60));

        await event.connect(this.alice).depositETH({value: ethers.utils.parseEther("1")});
        await expect(event.connect(this.alice).withdrawETH(ethers.utils.parseEther("1")))
            .to.emit(event, 'UserWithdrawn')
            .withArgs(this.alice.address, ethers.utils.parseEther("1"), 0);

        await event.connect(this.alice).depositETH({value: ethers.utils.parseEther("1")});
        await advanceTime(duration.hours(1));

        let tx = await event.connect(this.alice).withdrawETH(ethers.utils.parseEther("0.1"));
        let { logs } = await tx.wait();
        expect(BigNumber.from(`0x${logs[0].data.substr(66)}`).toNumber()).to.gt(0);

        await advanceTime(duration.hours(1));
        tx = await event.connect(this.alice).withdrawETH(ethers.utils.parseEther("0.1"));
        receipt = await tx.wait();
        expect(BigNumber.from(`0x${receipt.logs[0].data.substr(66)}`).toString()).to.equals("40000000000000000");
    })
})
