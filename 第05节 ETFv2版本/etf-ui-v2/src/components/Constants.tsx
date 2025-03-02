import { getAddress } from "viem";

const etfAddress = getAddress("0xA40B9AFc0DFDF3d5861B6a8d7d1c24b386C3f7cc");
const usdcAddress = getAddress("0x22e18Fc2C061f2A500B193E5dBABA175be7cdD7f");
const wethAddress = getAddress("0xfFf9976782d46CC05630D1f6eBAb18b2324d6B14");
const etfQuoterAddress = getAddress(
  "0x0c3E8403cCa75dAE02FCC5C3272dCB3d01d946c4"
);

export { etfAddress, usdcAddress, wethAddress, etfQuoterAddress };
