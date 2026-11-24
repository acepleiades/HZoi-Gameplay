# Vanilla inZOI romance reference

Observed on **Windows Steam v0.11.2**, build `20261027.16617.W`, on **2026-11-23**. This is a reference for HZoi Gameplay and other gameplay mods. It describes the base game. [Krafton's build notice](https://steamcommunity.com/app/2456740/announcements/).

**Cheating detection was unreliable in the tested v0.11.2 household.** Five witnessed bed trials produced no confirmed reaction. Later play produced two confirmed records, including one that assigned the caught role to Minah even though Jaewoo initiated every romantic interaction and autonomy was off. [Test conclusions](#conclusions-from-the-tests).

[Full interaction index (CSV)](inzoi-romance-interactions.csv) · [Marriage](#proposal-engagement-and-marriage) · [Children](#having-children) · [Cheating](#jealousy-and-cheating) · [Validation](#what-we-verified-in-game)

## Read the romance state correctly

Romance is a numeric stat on a relationship. Friendship, Family, and Business are separate stats. A named partnership is a separate piece of state. In English, **Sweetheart** is both the name of a positive score band (`romance6`) and the name of an established partner (`Youth_Lover` for young adults and older, `HighTeen_Lover` for the teen route). To identify a partner for gameplay, inspect the named relationship. The score, main relationship label, roommate status, and visible interaction labels are insufficient on their own.

| Romance score | Level | Stat relationship ID | English label |
| --- | ---: | --- | --- |
| −100 to below −90 | −3 | `romance1` | Worst Match |
| −90 to below −60 | −2 | `romance2` | Drifting Apart |
| −60 to below −30 | −1 | `romance3` | Lukewarm |
| −30 to below 30 | 0 | `romance4` | … (neutral band) |
| 30 to below 60 | 1 | `romance5` | Mutual Crush |
| 60 to below 90 | 2 | `romance6` | Sweetheart |
| 90 to 100 | 3 | `romance7` | True Love |

The table gives the boundaries configured in `RelationshipCondition`. At **60** and **90**, the game can pause progression for a relationship focus conversation. The positive choices include **Say You Want to Get Closer** at 60 and **Call Them Your True Love** / **Be Together as True Loves** at 90, depending on who initiates. These choices release the score checkpoint. **Ask Them to Become Your Sweetheart** is a separate interaction with a separate outcome that creates `Youth_Lover`. For example, its lower-Charisma route can already appear at 40 Romance with 30 Friendship.

The [Seoyun Ryu example](#seoyun-ryus-romance-menu) shows how to interpret the interaction menu. Check the pair's named relationship to confirm whether they have made it official.

Check both directions if the decision depends on how each Zoi feels. The debug setter used in testing writes both directions, but live relationship values can differ. A score's numeric band and the relationship names reported by the engine may also update at different times. Use actual score, relationship names, and flags as separate inputs.

## Interaction index

The [CSV](inzoi-romance-interactions.csv) lists **1,363 InteractionBag rows across 595 English labels** from the running build. It includes male/female and same-gender variants, refusal rows, romance conversations, dates, affection, proposals, wedding actions, pregnancy and adoption interactions, breakup/divorce, and infidelity reactions. Contextual entries such as pregnancy conversations, family affection, teen activities, and relationship-dependent alternatives are included so their gates can be compared. Routine friendship actions with no matching romance or family context and phone message bodies are outside this index.

Filter by **Group**, **English label**, or a **score band**. The same menu label can have several rows. **Named interaction** means the row has visibility or enable conditions, so its context still has to match. **Context or sequence entry** can be queued by an object, an event, or another interaction. **Automatic or hidden** includes actions such as the confrontation and other feedback rows.

Score-band cells show which scores can satisfy the row's explicit Romance predicates in the visibility and enable conditions. A dash rules out the band using those predicates. “Whole band” means some route is possible throughout the band, subject to other requirements. For example, the spouse version of **Suggest Having a Baby** has no Romance predicate and instead requires a Family score, and some actions drop their score requirement for formal partners. Square brackets include the endpoint, parentheses exclude it. Read the expanded predicates and branch conditions to distinguish appearance, enablement, refusal, and success. Where a clause compares the target's score, the projection assumes the two directions have the same score. For different scores, use the full predicates. Native conditions, autonomy, furniture and venue restrictions, menu selection, and queued branch weights can further narrow what happens.

### Common actions by first eligible score

| Score or state | Player-facing actions and requirements |
| --- | --- |
| **Around 0–19** | In an eligible pairing, **Say You Want to Get to Know Them Better** and **Express Attraction to Them** use a −1 to below 20 window. **Ask on a Date** can appear below 30 with a just-friends refusal. Some mood-specific actions such as **Hold Hands and Talk** have an earlier route. |
| **20** | **Kiss on Forehead** and **Give Heartfelt Hug** can succeed. **Peck** has a lower-score branch at 20 to below 30. **Ask Them About Their Ideal Type** and **Make a Bold Move** are examples of 20 to below 30 conversations. |
| **30** | **Peck** can succeed. **Hold Hands and Talk**, **Sit and Kiss**, **Kiss at the Table**, **Dance as Couple**, and **Share a Dance in Each Other's Arms** have qualifying routes, with furniture required where applicable. The normal successful **Ask on a Date** / **Plan Date Together** route opens, subject to time, availability and event conditions. **Kiss Passionately** uses this threshold for an uncommitted pair and requires the initiator to be Aflutter or Lovestruck. **Set the Mood Next to Bed** and **Set the Mood in Front of Tent** have eligible nonpartner routes at 30, with venue requirements. |
| **40** | **Kiss** has its successful deep-kiss animation. From 30 to below 40, a separate row can resolve to a refusal. **Ask Them to Become Your Sweetheart** can appear at 40. With Charisma 0–5 the 40–59 route needs Friendship ≥30. With Charisma ≥6 the row has no Friendship minimum, although it still checks romantic eligibility. |
| **50** | An eligible unmarried pair can **Suggest Having a Baby**. **Express Feelings** is one conversation in the 50 to below 70 window. |
| **60–61** | At 60, **Say You Want to Get Closer** can resolve the score checkpoint. The higher lower-Charisma confession route requires Romance ≥60 and Friendship ≥40. From 61, eligible formal partners can **Ask Them to Marry You**. **Set the Mood in Front of Sofa** and **Set the Mood in Front of Public Phone Booth** have a 61 threshold, compatible targets and venue checks. **Serenade** has a 61 score route plus earlier trait or mood routes. |
| **70 to below 90** | The dialogue pool adds options such as **Say You Want to Be Together Forever** and **Call Them the Best Person You've Ever Met**. Partners can still propose. Earlier score-window dialogue can drop out as the score rises. |
| **90–100** | The positive focus choice can advance the True Love checkpoint. **Pledge Eternal Love** and **Promise Your Feelings Will Never Change** have 90–100 windows. Eligible proposals use the high-score success branch. |
| **Established partner, fiancé, or spouse** | Several interactions have separate relationship-state routes. **Suggest Spending Time Together** checks `Youth_Lover` / `HighTeen_Lover` plus Romance ≥30, or Spouse plus Family ≥0. Some couple dances and furniture affection have a route at Romance ≥−30 for an established partner or fiancé, or Family ≥−30 for a spouse. The partner/fiancé adult bed route also has a −30 Romance minimum. |

The two similarly named kisses are different interactions. **Kiss** (`Co_DeepKiss_…_Success`) uses the deep-kiss montage and qualifies at 40 without a formal partner check. **Kiss Passionately** (`Co_Wedding_Kiss`) is an emotion-gated interaction with a 30 route for an uncommitted pair. **Give Kiss Performance** (`Co_Wedding_Kiss_01`) is a separate wedding-only action. [Krafton's v0.7.0 notes distinguish the passionate kiss and wedding performance](https://playinzoi.com/en/news/9824).

For app and event context, **Plan Date Together** routes into the Date social event. The `SocialEvent_Date` condition checks the `Date_Success` tag. The event template expects two `DateCouple` participants. Teen dates, visits, stayovers, calls and invitation messages have their own conditions. If extending phone behavior, start with `MobileCall` (including `Call_Receive_Romance_Lv0_*` through `Lv3_*`, `Call_*_Lover_*`, `Call_HighSchool_Date_*` and `Call_StayOver_Lover_*`) and the `CalendarEvent` / `SocialEventTemplate` tables. The CSV indexes interaction actions.

## Proposal, engagement, and marriage

1. **Create an adult partnership.** A successful **Ask Them to Become Your Sweetheart** adds `Youth_Lover`. The name can exist while the score is still in Mutual Crush.
2. **Propose at 61 Romance or higher.** **Ask Them to Marry You** requires `Youth_Lover`, romantic eligibility, and neither Zoi already engaged or married. The interaction also checks city-travel state. The 61 to below 90 rows allow refusal. The observed data weights are 80/20 for the ordinary branches and 70/30 for a trait-conditioned pair of branches. The ≥90 row has a single success branch when its prerequisites are met. A successful proposal adds `engagement`, removes the named lover relationships, and adds 5 Romance.
3. **Complete the marriage flow.** The engagement exposes marriage options subject to the native `CanMarrySuccess` check. The data has **Get Married** and **Plan Wedding Together**. Planning opens the Wedding social-event picker. The template expects the engaged couple and one officiant of at least Young Adult age, with attendants and guests optional. The Wedding creation script calls the native `Marriage` action and removes engagement. **Exchange Rings** and **Give Kiss Performance** are ceremony interactions. A successful proposal alone leaves the pair engaged.
4. **Read spouses through the Family relationship.** The game uses the Spouse relation and the Family score for many post-marriage interactions, including **Ask on a Date** (Family ≥0 on its spouse route), spouse affection, and trying for a baby. v0.2.0 specifically changed marriage to carry some of the existing relationship into Family. **Call Off Engagement** uses the engagement name. **Divorce** uses Spouse and the native divorce check, with separate outcome variants above and below −60 Family and a separate request flow. [Krafton's marriage score note](https://www.playinzoi.com/en/news/8812).

The official condition reference describes native marriage checks for existing spouses, age, separate family trees and relationship status. “Separate family trees” and “different households” are different questions. The wedding and native household-capacity behavior were not exercised end-to-end in the roommate save. [ModKit condition reference](https://mod-docs.playinzoi.com/docs/modkit-docs/wiki/script-condition/commands/).

## Having children

**Suggest Having a Baby** is the ordinary paired conception interaction. **Set the Mood** is a separate interaction sequence. Its visibility and success do not establish that the Try for Baby conditions were met.

| Relationship and score | Requirements and configured outcomes |
| --- | --- |
| **Unmarried, Romance 50 to below 60** | `Co_TryToHaveChildren_NoSpouse`. The row has no `Youth_Lover` or engagement requirement. Both must be at least Young Adults, the pair must pass romantic eligibility and the native pregnancy check, and the site must have an eligible double bed. The row weights are **21% conception-success route, 9% attempt without conception, 70% refusal dialogue**. |
| **Unmarried, Romance ≥60** | Same prerequisites. The row weights are **70% conception-success route, 30% attempt without conception**. |
| **Spouses, Family 10 to below 30** | `Co_TryToHaveChildren`. The row requires Spouse, a qualifying double bed and native eligibility. The row weights are **35% conception-success route, 15% attempt without conception, 50% refusal dialogue**. |
| **Spouses, Family ≥30** | Same prerequisites. The row weights are **70% conception-success route, 30% attempt without conception**. |
| **NPC-only spouses, Family ≥0** | A distinct row checks that neither is a player character, both have homes, both are no older than Adult, and the pregnancy and bed requirements are met. Its two configured weights are 80/20. |

For the ordinary paired route, both variants check the absence of success/failure test buffs for both participants and reject remote-city targets when enabling the interaction. The ModKit reference says native `CanPregnancy` also checks compatible physical sex (one female and one male), no existing pregnancy, minimum Young Adult age and household room. It blocks autonomous paired attempts involving the currently played household. Those are engine prerequisites in addition to the row conditions. An accepted attempt can still fail to conceive. The successful bed sequence applies the pregnancy-test success buff only if the prospective mother's household still has room. [ModKit condition reference](https://mod-docs.playinzoi.com/docs/modkit-docs/wiki/script-condition/commands/).

**Adopt a Child** and **Create a Child with Medical Help** are separate computer/laptop flows. Their object entries check home/household availability; physical adoption also checks Young Adult age and household capacity before opening the native flow. Krafton explicitly documented non-marital birth, adoption, and medical help, including an option to undertake medical help alone or with another Zoi. Consult the native picker for medical-help partner eligibility. A completed pregnancy reaches `ImminentBirth` for the childbirth interaction. [Krafton's v0.2.0 family changes](https://www.playinzoi.com/en/news/8812).

## Jealousy and cheating

**The normal affair witness becomes eligible when there is a named partner, fiancé or spouse relationship.** The game's `Condition[Cheat_Reaction_Howling]` accepts `HighTeen_Lover`, `Youth_Lover`, `engagement`, or family `Spouse`. It excludes a witness with the temporary `Exclude_Cheat` tag. There is no Romance score minimum in that condition, and the score's Mutual Crush, Sweetheart or True Love ID is not a substitute. Early autonomous flirting and kissing can therefore build several romance meters without activating this partner-witness path.

A qualifying interaction, an eligible witness and the spatial checks all matter. The game distinguishes multiple paths:

| Path | What the v0.11.2 rows say |
| --- | --- |
| **Confirmed** (`Howling_Affair_Confirmed`) | The successful deep-kiss row starts this proximity event. The separate **Kiss Passionately** animation and successful confessions can also start it through scripts. The row specifies radius 800 game units, same floor and a line trace. The reaction adds flags/records and can queue a three-Zoi confrontation. The ordinary trait branches can set Romance and Family to −100. The `Flirt` trait group has a different reaction that skips that score-setting branch while still receiving cheating-related state. |
| **Suspicion** (`Howling_Affair_Suspicion`) | Shares the named-partner and spatial filters, but the first qualifying event can add `Affair_Suspicion`. Another while that flag is present can add `Watch_Cheat`, record the incident, and escalate. The flag row gives a 1,440-minute lifetime. |
| **Other witness paths** | `Howling[Cheat_Reaction_Howling]` checks the same named-partner condition but has radius 500, same floor and no line trace. Its reaction applies a 50-point reduction to the relevant relationship stat. A separate on-date row checks `IsDatePartner` and can end the date. The legacy spouse-`Affair` buff and spouse-only range reactions are separate. Do not generalize any single distance, score penalty or action list to all routes. |
| **Repair** | **Ask for Forgiveness** checks cheating flags and the relationship. Successful forgiveness can remove witness flags and recover part of the damaged relationship. |

For **Set the Mood Next to Bed**, the `Co_TryTo_Mood` sequence calls the confirmed-affair event through `Mood_Success_Relationship` after the approach conversation and through `Start_Howling_Affair_Confirmed` when the bed step begins. It temporarily tags the two participants `Exclude_Cheat` and removes their affair emitters and exclusion tags at the end. The nearby **Make Love Surprise** event uses its own conditions and skips the line trace. Its receipt establishes proximity for that event. The [bed witness trials](#set-the-mood-witness-trials) covered seated and standing partners.

Both accepted **Suggest Having a Baby** sequences (`Co_TryToHaveChildren_Success` and `Co_TryToHaveChildren_Fail`) run `TryToHaveChildren_Success_Relationship` after the approach conversation and call `Start_Howling_Affair_Confirmed` at the start of the bed step. The approach script adds 10 Romance on the unmarried route. The live save contained confirmed cheating records after the [player's follow-up](#player-follow-up-with-suggest-having-a-baby).

The scores and flags are stronger evidence of detection than a visible angry animation. `Watch_Cheat` on the witness, `Witnessing_Cheating` on the involved Zoi, and records such as `Cheating_Found_Target` help distinguish detection from an unrelated emotional reaction. **Kissing can happen without an affair reaction**, and multiple named partnerships can coexist. The native autonomy option `AllowAffair` controls frequency of autonomous flirting/affairs. Its documented purpose is different from a specific partner agreeing to nonexclusivity.

Krafton documented a partner score penalty, approach reaction and an apology route in June 2026. Its November developer letter discussed a future system for other people witnessing infidelity and spreading the news. The partner-witness rule above should not be used to predict that future bystander system. [v0.9.0 patch notes](https://playinzoi.com/en/news/10165) · [November developer letter](https://forum.playinzoi.com/t/topic/18328) · [Howling filter semantics](https://mod-docs.playinzoi.com/docs/modkit-docs/wiki/luaapi/b1/structs/fb1howlingtablerow/).

## What we verified in game

### Roommate household tests

At 45 Romance, before any formal partnership, we queued the successful **Kiss** directly through the game MCP for Jaewoo and Minah. The deep kiss played, Minah's Romance with Jaewoo rose to 51.4, and Xinyu's stayed at 45. We later queued the same kiss after commitment with Xinyu nearby on the same floor. The kiss played again and produced no observed cheating flag, record, confrontation, or score penalty.

A successful confession with Xinyu gave Jaewoo the named `Youth_Lover` relationship. The partnership persisted after we set their Romance back to 45, within **Mutual Crush**. A later successful confession with Minah gave Jaewoo a second `Youth_Lover` relationship while the first remained active.

At about 81 Romance with a formal partner, we opened the live Romance menu. Both **Ask Them to Marry You** and **Suggest Having a Baby** were enabled. The check stopped at the menu.

### Set the Mood witness trials

We ran five trials of **Set the Mood Next to Bed** from the normal Romance menu on Steam v0.11.2 at Gaya Apartments, 102, with SceneZOI mounted. In the reloaded Kwon household, Jaewoo started at 0 Romance with Xinyu, Seoyun, and Minah. We boosted each score to 29 within the neutral band, used **Kiss on Forehead** to enter **Mutual Crush**, then boosted within that tier to 58. **Ask Them to Become Your Sweetheart** established each `Youth_Lover` partnership. Minah accepted on the second ask after we restored her Romance to 58. In the first four trials, the witnesses had `Youth_Lover` in both directions and a score of 60 at the pending **Mutual Crush** checkpoint.

Jaewoo first selected **Set the Mood Next to Bed** with Seoyun while Xinyu sat in the lounge chair facing the double bed. The sequence ended at 07:13 in-game. Xinyu registered `howling_MakeLove_Surprise`. Her Romance stayed at 60 in both directions, and we found no cheating flag, record, or confrontation. Jaewoo logged `Record_SetMode_Fail` toward Seoyun, while Seoyun logged `Record_SetMode_Success` toward Jaewoo.

After Minah became Jaewoo's third formal partner, he repeated the interaction with her while Seoyun sat in the same chair and Xinyu moved away from the bedroom. The sequence ended at 07:18 and both participants logged `Record_SetMode_Success`. Seoyun's event cooldown maps stayed empty and her Romance stayed at 60 in both directions, with no cheating flag, record, or confrontation.

Jaewoo then started the interaction with Xinyu at 07:25 while Minah and Seoyun stood by the dresser near the empty lounge chair. Both witnesses were on the same floor as the bed and stayed in place. They began with empty event cooldown maps and no cheating flags, records, or related moodlets. Both participants logged `Record_SetMode_Success` at 07:26:41. Both witnesses retained `Youth_Lover` and 60 Romance in both directions, their cooldown maps stayed empty, and we found no cheating flag, record, moodlet, or confrontation. This trial used the existing partnerships without further cheats and changed the bed partner, witness count, and witness positions from the seated trials.

After restarting the game, Jaewoo repeated the standing trial with Xinyu at 07:33 using the same build and existing partnerships. At launch neither witness had a confirmed-affair cooldown entry, cheating flag, or cheating record. Minah's older `effect_Howling_Mood_After` entry persisted through the reload. Both witnesses stayed by the dresser. The bed sequence ended at 07:34 and the participants received fresh `Buff_Mood_Success` variants while their prior relationship record timestamps stayed the same. Minah registered `howling_MakeLove_Surprise` and received `Show_MakeLove`. Seoyun's event cooldown maps stayed empty. Through 07:35 both witnesses retained `Youth_Lover` and 60 Romance in both directions, with no new cheating flag, record, moodlet, or confrontation.

For the final trial, Jaewoo used **Say You Want to Get Closer** with each partner. All three relationships reached **Sweetheart** (`romance6`) and retained `Youth_Lover` in both directions. We teleported Zois back to approximate starting positions and used **Move Here** to adjust the witnesses' facing. When Jaewoo started the interaction with Xinyu at 07:52, Minah stood 183 game units horizontally from the center of the bed, facing about 12° off center and about 87 units from her original marker. She had no `Exclude_Cheat` tag. She stayed in place, while Seoyun moved into the hall before the bed animation began. Both participants received fresh `buff_Mood_Success_02` applications after the sequence ended at 07:53. Minah registered a new `howling_MakeLove_Surprise` and `show_MakeLove`. She retained `Youth_Lover` and `romance6` in both directions with no confirmed-affair event, cheating flag, record, moodlet, confrontation, or score penalty.

#### Starting positions before the Sweetheart-tier trial

All six Zois were on floor 0 at world Z = 3236.92554. Their rotations were yaw only. The teleport command takes world coordinates. Use yaw as a reference when manually turning a Zoi afterward.

| Zoi | World X | World Y | Yaw (degrees) |
| --- | ---: | ---: | ---: |
| Jaewoo Kwon | 162129.86043 | -72840.99005 | -113.74700 |
| Xinyu Yang | 162089.42405 | -72932.90178 | 66.25300 |
| Minah Koo | 162216.77584 | -72736.64487 | -165.92764 |
| Seoyun Ryu | 162226.24033 | -72793.00586 | 172.68051 |
| Kako Fujita | 162606.32960 | -72635.18786 | -23.74448 |
| Yiming Yang | 162523.46793 | -72947.63695 | 138.25301 |

### Seoyun Ryu's Romance menu

The screenshot shows **Seoyun Ryu** (Kwon Family) with **Ask Them to Become Your Sweetheart** visible at the top of the Romance menu. The adult visibility rules for this action exclude a current `Youth_Lover` or `engagement` relationship between the pair. Seeing the action suggests that the pair has yet to establish a formal adult partnership. A successful ask would establish `Youth_Lover`. **Sweetheart** on the Romance meter would describe the score band from 60 to below 90.

The same menu shows **Suggest Having a Baby**, **Set the Mood Next to Bed**, **Kiss at the Table**, **Kiss Passionately** (tagged **Lovestruck**), **Ask on a Date**, **Kiss on Forehead**, **Sit and Kiss**, **Peck**, and **Give Heartfelt Hug**. These options have routes available before commitment. The capture establishes which labels were visible. It leaves the pair's Romance score, named relationship, and any interaction outcome unverified.

### Player follow-up with Suggest Having a Baby

The player confirmed that autonomy was off for all six household members. Only Jaewoo, Xinyu, Minah, Seoyun, Kako, and Yiming were in the apartment. The other Zois were idle between directed actions, and Jaewoo initiated every romantic interaction.

In the Kwon household, the player used **Kiss Passionately** with Jaewoo's `Youth_Lover` partners in front of each other and saw no cheating reaction at the time. An initial **Suggest Having a Baby** attempt produced a toast saying the action was unavailable at that moment. The player suspected someone in the bedroom was blocking the attempt and moved Xinyu, Seoyun, and Minah to the living, dining, and kitchen area (LDK). The cause of that toast was never isolated.

With the other partners nearby in the LDK, Xinyu accepted **Suggest Having a Baby**. The pair stopped before the bed step. The player observed a cheating reaction involving Xinyu around that attempt. Seoyun accepted the next attempt and became pregnant. When the player went to try with Minah, they found that a cheating reaction involving her had already happened. The player reported that Minah was off-screen in another room and associated the result with the attempt involving Seoyun. They took the different-room result as evidence that direct sight might be unnecessary.

Read-only inspection of the live save at 08:12 confirmed separate cheating records for the two pairs. At 08:00:17, Xinyu received `Cheating_Found_Self` toward Jaewoo, the first-found-cheating milestone, and an `effect_Affair_Confirmed` cooldown entry. Jaewoo received `Cheating_Found_Target` toward Xinyu, the first-caught-cheating milestone, and `buff_Caught_Cheating_03`. The player's screenshot of Jaewoo's Flustered mood showed **What Should I Do?** and **Infidelity Exposed**, both acquired 12 in-game minutes earlier. Both directions of the pair's Romance were −90 at inspection, while Family was near −100. Xinyu still had the `TryToHaveChildren` tag from the approach script. Its 30-minute expiry places the +10 Romance effect about ten in-game seconds after the cheating record, consistent with the player's explanation for the −90. Seoyun had fresh pregnancy success and pregnancy start buffs, with pregnancy start recorded at about 08:03:06.

The Minah pair had a second cheating record at 08:03:17, with Romance and Family both about −99.99 in both directions at inspection. Jaewoo received `Cheating_Found_Self`, the first-found-cheating milestone, and an `effect_Affair_Confirmed` cooldown entry. Minah received `Cheating_Found_Target`, the first-caught-cheating milestone, and `buff_Caught_Cheating_03`. The game recorded Jaewoo as the witness and Minah as caught about 11 in-game seconds after Seoyun's pregnancy started. The assigned roles conflict with the player's account that Jaewoo drove all romantic activity and Minah was idle in another room. The confirmed-affair script assigns roles from the Zois it receives for each proximity event. The save preserved the assigned roles and penalties, and the source of the event remains unknown. All three pairs still carried `Youth_Lover` in both directions at inspection.

### Conclusions from the tests

Jaewoo could hold multiple named `Youth_Lover` relationships at once, including while a partner's Romance meter still showed **Mutual Crush**. **Ask Them to Become Your Sweetheart** created the named partnership, and **Say You Want to Get Closer** later advanced the meter to `romance6`. Romantic actions were visible alongside the confession option in Seoyun's screenshot. The live menu at about 81 Romance confirmed that a formal partner could be offered both marriage and an attempt to have a baby before marriage. The follow-up verified an unmarried pregnancy with Seoyun. The proposal check ended at the menu.

All five normal-menu bed trials reached the step that calls the confirmed-affair event. None produced a confirmed cheating reaction. Xinyu registered the separate surprise event in the first trial, and Minah registered it after the restart and again at `romance6`. Both the restart and the move to `romance6` left the confirmed detection result unchanged in this household. The Sweetheart-tier result applies to Minah, who stayed by the bed after Seoyun left.

The follow-up shows that an interaction without an immediate observed reaction can be followed by confirmed detection during continued play. The player suspects that continuing romantic interactions around named partners makes eventual detection likely. The runs establish that it can happen and leave its probability, the causal action for each detection, and any cooldown effect unmeasured. The confirmed-affair effect pool has a configured 20-second cooldown. [ModKit effect cooldown reference](https://mod-docs.playinzoi.com/docs/modkit-docs/wiki/luaapi/b1/structs/fb1howlingeffecttablerow/).

The Minah incident shows that a cheating result can be discovered with the other Zoi off-screen in a different room. The `effect_Affair_Confirmed` entry points to the confirmed-affair route, whose proximity row checks a line trace. `Cheat_Reaction_Howling` and the bed-trial surprise event skip that check. The follow-up did not capture the confirmed-affair trace at the moment it ran. The two records also show that severe Romance penalties can coexist with the named `Youth_Lover` relationship.

The game rolls the participants' post-bed reactions separately, after the confirmed-affair call at the start of the bed step. The first trial recorded a success for one participant and a failure for the other. In repeat runs, fresh success buffs showed the outcome even when prior record timestamps stayed the same. A participant's result and a witness's reaction therefore need separate checks.

The witnessed **Kiss** result applies to a directly queued deep kiss. The witness reaction and timing for a kiss launched through the normal menu remain unverified.

**The v0.11.2 tests show unreliable detection and inconsistent role assignment in this household.** Formal partners stayed near completed bed encounters without a confirmed cheating result. During continued play, the game applied severe relationship penalties and recorded roles that conflicted with the observed actions involving Minah. The underlying cause and the frequency of these outcomes remain unknown.

### Remaining validation

The ceremony, adoption, and childbirth described above still await end-to-end in-game validation. The follow-up verified pregnancy and severe penalties associated with cheating records. The exact event that produced the Minah record and the general rules for when nearby partners detect cheating remain open.

A future reproduction should use the normal interaction menu with a rested, idle established partner in the same unobstructed room. Capture both directions' relationship state and the witness's queue before and after the action. Test successful **Kiss**, emotion-gated **Kiss Passionately**, and a suspicion-triggering action separately. Repeat with the witness on a different floor and with an uncommitted pair. Use a debug command to set up state only, or label the entire trial as a direct-queue test if the interaction is also queued through a command.

## Keep this reference current

- Capture the actual game build before interpreting row changes. The English labels here came from the ModKit's `Blue_Data` and `Blue_UI` string catalogs. Older guides can describe different thresholds and interactions.
- Read `RelationshipCondition[RelationshipCondition]` for score bands, `Relationship` for named relations, and `InteractionBag` plus `Condition` for menu gates. Follow each bag's sequence to `CoopTalk`, `Interaction`, `Action`, and `Script` for outcomes. Inspect `Howling`, `HowlingEffect`, `RelationshipFlag` and `RelationshipRecord` for witnessed consequences. Use `SocialEventTemplate` for scheduled roles and prerequisites.
- The CSV is a screening index of the 12,698 live `InteractionBag` rows. It includes entries selected by romance and event tags, romance score or named partner predicates, and romance, spouse, date, wedding, pregnancy, breakup and affair IDs. It includes native variants for traceability. Its score columns project explicit visibility and enable conditions; it retains separate enqueue and branch identifiers for follow-up. It does not copy game scripts or assets.
- For the gameplay add-on, keep willingness, relationship score, established relationship, and a per-partner agreement as separate facts. A base-game trait, `AllowAffair`, or the existence of two lover names does not encode that agreement. Apply any future change to the appropriate pair and distinguish detection eligibility, the partner's emotional response and the consequences.
