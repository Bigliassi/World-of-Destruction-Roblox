# World of Destruction (Roblox) — Version 1.0 Monetization Plan & Strategy

This document details the complete **Version 1.0 Roblox Monetization Architecture** implemented in `src/ServerScriptService/MonetizationService.script.luau` and `src/StarterGui/TutorialAndGuideUI.client.luau`, covering **GamePasses**, **Developer Products**, **Studio Sandbox Testing**, **Roblox Engagement-Based Payouts (EBP)**, and step-by-step instructions for swapping placeholder IDs with live Robux Asset IDs.

---

## 1. Monetization Design Philosophy

1. **100% Complete & Generous Free Base Game:** Every player can earn Cash, climb all 50 Levels to *Lord of Destruction*, unlock the core vehicle roster, and max out all 5 Speed Shop upgrade tracks purely through gameplay.
2. **High-Excitement Value Perks (GamePasses):** Permanent purchases offer immediate, tangible quality-of-life excitement (2x Cash/XP, Unlimited Blue Plasma Nitro, Golden Apex Bulldozer, Police Heat Shield Scanner, and Mega Combo Magnet).
3. **Instant Action Consumables (Developer Products):** Low-friction repeatable purchases for players who want an instant Cash injection, an emergency 5-Star Police Bribe, or an instant Max Repair + 60-Second 2x Overdrive boost during intense chases.
4. **Zero-Config Studio Sandbox Testing:** Every GamePass and Developer Product works **out of the box in Roblox Studio** before any Robux IDs are published. Clicking any item in the **`[M] VIP Store`** inside Roblox Studio immediately grants the perk or consumable for free so you can test every feature right away.

---

## 2. GamePasses Catalog (Permanent One-Time Purchases)

Configured in `MonetizationService.script.luau` under `GAMEPASS_CATALOG`:

| Key | Display Title | Suggested Price (Robux) | Player Benefit & Technical Hook |
| :--- | :--- | :---: | :--- |
| **`VIP2xCash`** | **VIP 2x Cash & XP** | **399 R$** | Permanently doubles `CashMagnetMultiplier` (×2.0) and `XPMultiplier` (×2.0) across all destructions, combos, stunts, and missions. |
| **`UnlimitedNitro`** | **Unlimited Plasma Nitro** | **299 R$** | Sets `UnlimitedNitro = true` and `NitroFlameColor = "BluePlasma"`. Nitro meter stays locked at 100% and never depletes. |
| **`GoldenBulldozerPass`** | **Golden Apex Bulldozer** | **499 R$** | Unlocks `goldenBulldozer` and `boxTruck` (Goliath Rig) immediately with 24K Gold trim attributes persisted to `PlayerDataService`. |
| **`HeatShieldScanner`** | **Police Heat Shield Scanner** | **249 R$** | Dampens incoming `HeatProgress` buildup by **50%** (`HeatBuildupMultiplier = 0.5`) and speeds up police evasion by **50%**. |
| **`MegaMagnetPass`** | **Mega Combo & Cash Magnet** | **199 R$** | Doubles the active Chaos Combo timer window from **4.5s → 9.0s** (`ComboMaxTime = 9.0`) and adds a permanent **+50% Cash Magnet** bonus. |

---

## 3. Developer Products Catalog (Repeatable Consumables)

Configured in `MonetizationService.script.luau` under `DEVPRODUCT_CATALOG` and processed via `MarketplaceService.ProcessReceipt`:

| Key | Display Title | Suggested Price (Robux) | Player Benefit & Technical Hook |
| :--- | :--- | :---: | :--- |
| **`CashPackStarter`** | **Starter Cash Pack (+$10,000)** | **49 R$** | Fires `AddCashEvent` for **+$10,000 Cash** (ideal for early Speed Shop upgrades or unlocking mid-tier cars). |
| **`CashPackPro`** | **Pro Cash Vault (+$50,000)** | **199 R$** | Fires `AddCashEvent` for **+$50,000 Cash** (enough to max out multiple Speed Shop upgrade tracks). |
| **`CashPackTycoon`** | **Tycoon Mega Crate (+$250,000)** | **699 R$** | Fires `AddCashEvent` for **+$250,000 Cash** (unlocks every vehicle and maxes the entire Speed Shop garage). |
| **`BribePoliceChief`** | **Bribe Police Chief (Clear Heat)** | **35 R$** | Impulse-saver during 4★–5★ chases: instantly resets `HeatStars` and `HeatProgress` to `0` and despawns pursuing police units. |
| **`InstantMaxRepairAndBoost`** | **Max Repair + 60s Overdrive** | **29 R$** | Instantly restores vehicle HP to 100%, refills Nitro to 100%, and activates a **60-second 2x Cash & 1.5x XP Overdrive** boost! |

---

## 4. Roblox Engagement-Based Payouts (Premium Payouts) & Retention Loops

On Roblox, **Engagement-Based Payouts (EBP)** reward experiences based on the share of session time spent by **Roblox Premium** subscribers. World of Destruction v1.0 maximizes session length and repeat retention through four interlocking loops:

1. **The "Just One More Combo" Loop (30–90 seconds):**
   - The 4.5s dynamic combo timer + 10x OVERDRIVE tier + 25% Combo Bank Bonus keeps players chaining blocks, hydrants, and ramps continuously.
2. **Cycling Live Chaos Missions (Every 60 seconds):**
   - Automatic mission rotation (`ChaosAndEconomyService`) ensures that as soon as a player finishes upgrade shopping, a fresh timed challenge (*"Wreck 3 Police Cruisers!"*, *"Smash 10 Fire Hydrants!"*) begins after a 6-second intermission.
3. **5-Track Speed Shop + 8-Vehicle Garage Arc (20–60 minutes):**
   - Upgrading Engine, Armor, Nitro, Plow, and Magnet from Level 1 to Level 5 visibly transforms how fast the car drives and how effortlessly it plows through heavy landmarks like **Leo Tower**.
4. **50-Level Prestige Progression (Multi-Session Retention):**
   - Climbing from *Lv.1 Street Rookie* to *Lv.50 Lord of Destruction* provides constant XP bar movement, celebratory 3D level-up shockwaves, and escalating Cash jackpots up to **+$50,000**.

---

## 5. How to Swap Placeholder IDs (`0`) with Live Roblox Asset IDs

When you are ready to publish for live Robux transactions:

1. Publish the place to Roblox (**File → Publish to Roblox As...**).
2. Open the [Roblox Creator Dashboard](https://create.roblox.com/) and select your **World of Destruction** experience.
3. Navigate to **Monetization → Passes**:
   - Create the 5 GamePasses listed in Section 2 above and copy each generated **Pass ID**.
4. Navigate to **Monetization → Developer Products**:
   - Create the 5 Developer Products listed in Section 3 above and copy each generated **Product ID**.
5. Open `Roblox/src/ServerScriptService/MonetizationService.script.luau` and replace `PassId = 0` and `ProductId = 0` in `GAMEPASS_CATALOG` and `DEVPRODUCT_CATALOG` with your live numeric IDs:
   ```luau
   {
       Key = "VIP2xCash",
       PassId = 123456789, -- <-- Paste your live Roblox Pass ID here
       Title = "VIP 2x Cash & XP",
       PriceRobux = 399,
       ...
   }
   ```
6. Rebuild the place file (`python3 Roblox/tools/build_rbxlx.py`) and publish to Roblox!
   - On live Roblox servers (`not RunService:IsStudio()`), clicking any item in the `[M] VIP Store` will automatically open the official Roblox Robux purchase prompt (`MarketplaceService:PromptGamePassPurchase` / `PromptProductPurchase`).
   - Inside Roblox Studio, Sandbox Mode remains available so you can always test without spending Robux.
