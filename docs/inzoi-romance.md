# Vanilla inZOI romance reference

Observed on **Windows Steam v0.11.2**, build `20261027.16617.W`, on **2026-11-23**. This is a reference for HZoi Gameplay and other gameplay mods. It describes the base game. [Krafton's build notice](https://steamcommunity.com/app/2456740/announcements/).

**Cheating detection appears unreliable in v0.11.2.** The tests suggest that repeated romance with another Zoi near a formal partner will most likely trigger detection eventually. [Test conclusions](#conclusions-from-the-tests).

[Full interaction index (CSV)](inzoi-romance-interactions.csv) · [Marriage](#proposal-engagement-and-marriage) · [Children](#having-children) · [Set the Mood](#set-the-mood-next-to-bed-menu-rules) · [Cheating](#jealousy-and-cheating) · [Validation](#what-we-verified-in-game)

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

The adult **Ask Them to Become Your Sweetheart** option excludes existing `Youth_Lover` and `engagement` relationships between the pair. Check the named relationship to confirm whether they have made it official.

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

## Set the Mood Next to Bed menu rules

The native Romance menu lists the adult bed rows `Co_TryTo_Mood_Lover` and `Co_TryTo_Mood_Spouse`. The row has three separate stages worth checking when an option is missing, disabled, or selected and then fails.

| Stage | Native rules |
| --- | --- |
| Visibility | `CanMood_Lover_Bed` excludes family relationships. The initiator needs Romance ≥−30 with a `Youth_Lover` or `engagement` partner, or Romance ≥30 with any other eligible partner. `CanMood_Spouse_Bed` requires Spouse and Family ≥−30. Both check `IsLovable` and whether the initiator's site has an object with the `Bed_Double_ForCondition` template tag. Both bags use age mask 480 (`Youth`, `Adult`, `Old`, `Elderly`). The lover condition explicitly checks that both Zois are at least `Youth`. |
| Enabled | The row's visibility condition must still pass. `Not_FromRemoteCity_SelfTarget` also checks both Zois. |
| Enqueue and answer | Both adult bed rows have an empty `EnqueueConditionIds` list. `RequestCoop` uses the configured answer branches to schedule `Co_TryTo_Mood` or `Co_TryTo_Mood_Fail`. |

The site tag is the declared venue check for showing the option. The visible condition leaves bed distance, room occupancy, path, access permissions, and home ownership out of its explicit rules. `IsLovable` and the site-tag lookup are native predicates. Their internal checks and the exact site boundary for a Zoi standing outdoors have yet to be verified. When the native invitation succeeds, the co-op later looks for `Sleep_Bed` with `TargetFilter[AutoFind_Double_Bed]`. The filter uses `NearTarget`, `searchRange=0` and `bOnlySameZoneTarget=false`. The meaning of a zero range in this filter has yet to be measured. [ModKit condition reference](https://mod-docs.playinzoi.com/docs/modkit-docs/wiki/script-condition/commands/) · [Interaction branches](inzoi-romance-interactions.csv).

Among qualifying pairs, the configured acceptance chance is 70% for a named partner or fiancé below 30 Romance and 100% from 30. An uncommitted partner with a negative emotional tendency at 30–60 Romance has a 30% chance of accepting. At those same scores, neutral or positive partners take the acceptance branch, as do qualifying uncommitted partners with Romance ≥61. Spouses have a 70% acceptance chance below 30 Family and 100% from 30. The relationship checks read the initiator's score for the selected target. The live apartment menu showed the lover row enabled in both directions for Jaewoo and Yiming.

HZoi Gameplay's **Have Sex** and **Have Sex Here** use the game's `IsLovable` predicate, the same Romance and Family thresholds, and the remote-city check. Those checks determine eligibility for the HZoi entry points. The age mask and double-bed tag in the table above belong to the original inZOI action. **Have Sex** uses the clicked partner and searches for a venue. **Have Sex Here** opens the native picker only if someone qualifies and rechecks the pair on **Invite**. At Nuri Plaza, an eligible pair could select **Have Sex** in either direction. HZoi's search ended before the invitation because the plaza had no reachable residential venue in scope. See the [encounter design](encounter-design.md#player-interaction) for availability and final privacy.

Native **Set the Mood** uses `Positive_Talk`. The game's `Emotion` table disables that tag at level 3 for `Sad`, `Uneasy`, `Cringing`, `Irritated`, and `Worried`. The live menu showed **Cannot Be Used While Feeling Miserable** for a Sad level 3 initiator. HZoi uses the corresponding restrictions for the initiator on both entry points. The target's mood affects the response weights above.

## Set the Mood Romance effects

When the native scheduler takes over an HZoi invitation, the starter can report `Coop` cancellation as the scheduler begins the approach. HZoi verifies the scheduler's origin and both participants before treating this as a handoff. A refusal affects Romance only after both native dialogue roles finish. [ModKit co-op scheduler reference](https://mod-docs.playinzoi.com/docs/modkit-docs/wiki/luaapi/b2/structs/fb2coopscheduler/).

After the **Set the Mood Next to Bed** acceptance conversation, `Co_TryTo_Mood` calls `Mood_Success_Relationship`. The inspected game row adds 10 Romance for a pair without a family relationship, or 10 Family for a pair with a family relationship. The refused sequence calls `TryToHaveChildren_Fail_Talk`, which subtracts 5 Romance for a pair without a family relationship or 5 Family for spouses. Both use an `AddRelationship` command with the initiator as Self, the partner as Target, and the game's normal relationship limits. The later bed step runs `Mood_Success` for effects such as moodlets and needs. The score delta can depend on native modifiers and limits. [ModKit AddRelationship reference](https://mod-docs.playinzoi.com/docs/modkit-docs/wiki/script-execution/exec-addrelationship/).

[HZoi Gameplay’s Romance policy](encounter-design.md#romance-changes) uses the native stat and additive command for refusal and verified scene outcomes. The co-ops reuse the native conversation rows. HZoi Gameplay runs just the relationship effect, so the native conversation’s other effects, such as emitting an affair event on acceptance, stay outside this payout.

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

Jaewoo held three official `Youth_Lover` relationships at once. The named partnership persisted at 45 Romance (**Mutual Crush**) and after cheating penalties near −100. **Say You Want to Get Closer** advanced the Romance meter to `romance6`. At about 81 Romance, **Ask Them to Marry You** and **Suggest Having a Baby** were enabled for a formal unmarried partner. The proposal check ended at the menu.

### Set the Mood witness trials

Five normal-menu **Set the Mood Next to Bed** trials with SceneZOI mounted reached the bed step with a same-floor `Youth_Lover` witness nearby and produced zero confirmed detections. This held for seated and standing witnesses, after a restart, and at `romance6`. Three runs registered the separate `howling_MakeLove_Surprise` event. Fresh success buffs confirmed participant outcomes on repeats when relationship record timestamps stayed the same.

### Player follow-up with Suggest Having a Baby

Only the six household Zois were present, autonomy was off, and Jaewoo initiated every romantic action. **Kiss Passionately** in front of formal partners drew no immediate reaction. A separately tested, directly queued **Kiss** also produced no confirmed detection.

Xinyu accepted **Suggest Having a Baby**, and the pair stopped before the bed step. The save confirmed that Xinyu caught Jaewoo. Their Romance was −90, consistent with the accepted conversation adding 10 after detection. Seoyun conceived on the next attempt. Eleven in-game seconds after her pregnancy began, the save recorded Jaewoo as witness and Minah as caught, with Romance near −100 in both directions. Minah was reportedly idle in another room. The trigger and line trace for that event remain unknown.

### Conclusions from the tests

**Cheating detection appears unreliable in v0.11.2.** The working conclusion is that repeated romance with another Zoi near a formal partner will most likely trigger detection eventually. The tests leave the odds and exact trigger unknown. Verify detection using `effect_Affair_Confirmed`, the witness and caught records, and Romance in both directions.

## Keep this reference current

- Capture the actual game build before interpreting row changes. The English labels here came from the ModKit's `Blue_Data` and `Blue_UI` string catalogs. Older guides can describe different thresholds and interactions.
- Read `RelationshipCondition[RelationshipCondition]` for score bands, `Relationship` for named relations, and `InteractionBag` plus `Condition` for menu gates. Follow each bag's sequence to `CoopTalk`, `Interaction`, `Action`, and `Script` for outcomes. Inspect `Howling`, `HowlingEffect`, `RelationshipFlag` and `RelationshipRecord` for witnessed consequences. Use `SocialEventTemplate` for scheduled roles and prerequisites.
- The CSV is a screening index of the 12,698 live `InteractionBag` rows. It includes entries selected by romance and event tags, romance score or named partner predicates, and romance, spouse, date, wedding, pregnancy, breakup and affair IDs. It includes native variants for traceability. Its score columns project explicit visibility and enable conditions; it retains separate enqueue and branch identifiers for follow-up. It does not copy game scripts or assets.
- For the gameplay add-on, keep willingness, relationship score, established relationship, and a per-partner agreement as separate facts. A base-game trait, `AllowAffair`, or the existence of two lover names does not encode that agreement. Apply any future change to the appropriate pair and distinguish detection eligibility, the partner's emotional response and the consequences.
