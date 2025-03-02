import "@rainbow-me/rainbowkit/styles.css";
import "../App.css";
import {
  getDefaultConfig,
  RainbowKitProvider,
  ConnectButton,
} from "@rainbow-me/rainbowkit";
import { WagmiProvider, http } from "wagmi";
import { sepolia } from "wagmi/chains";
import { QueryClientProvider, QueryClient } from "@tanstack/react-query";
import { useState } from "react";
import { InvestTabMulti } from "./InvestTabMulti";
import { RedeemTabMulti } from "./RedeemTabMulti";
import { InvestTabSingle } from "./InvestTabSingle";
import { RedeemTabSingle } from "./RedeemTabSingle";

const config = getDefaultConfig({
  appName: "BlockETF",
  projectId: "5389107099f8225b488f2fc473658a62",
  chains: [sepolia],
  ssr: true, // If your dApp uses server side rendering (SSR)
  transports: {
    [sepolia.id]: http(
      "https://eth-sepolia.g.alchemy.com/v2/kGFeN--CkJ791I8qeNEeRHAdb0gBbq8z"
    ),
  },
});

const queryClient = new QueryClient();

export const Web3Provider = () => {
  const [activeTab, setActiveTab] = useState("invest");
  const [useUnderlyingAssets, setUseUnderlyingAssets] = useState(true);

  return (
    <WagmiProvider config={config}>
      <QueryClientProvider client={queryClient}>
        <RainbowKitProvider>
          <div className="app-container">
            <header className="navbar">
              <div className="navbar-logo">
                <h1>BlockETF</h1>
              </div>
              <ConnectButton />
            </header>
            <div className="main-content">
              <div className="card">
                {/* Tabs */}
                <div className="tab-header">
                  <button
                    className={activeTab === "invest" ? "active" : ""}
                    onClick={() => setActiveTab("invest")}
                  >
                    Invest
                  </button>
                  <button
                    className={activeTab === "redeem" ? "active" : ""}
                    onClick={() => setActiveTab("redeem")}
                  >
                    Redeem
                  </button>
                </div>
                {/* Switch */}
                <div className="switch-container">
                  <label className="switch">
                    <input
                      type="checkbox"
                      checked={useUnderlyingAssets}
                      onChange={(e) => setUseUnderlyingAssets(e.target.checked)}
                    />
                    <span className="slider round"></span>
                  </label>
                  <label className="form-label">With underlying tokens</label>
                </div>
                {/* Content */}
                <div className="content">
                  {activeTab === "invest" ? (
                    useUnderlyingAssets ? (
                      <InvestTabMulti />
                    ) : (
                      <InvestTabSingle />
                    )
                  ) : activeTab === "redeem" ? (
                    useUnderlyingAssets ? (
                      <RedeemTabMulti />
                    ) : (
                      <RedeemTabSingle />
                    )
                  ) : null}
                </div>
              </div>
            </div>
          </div>
        </RainbowKitProvider>
      </QueryClientProvider>
    </WagmiProvider>
  );
};
