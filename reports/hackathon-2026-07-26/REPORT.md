# JacHammer Hackathon — Full Report
**Window:** 2026-07-26 17:00 → 2026-07-27 03:30 UTC (10.5 h — corrected end time) · **Env:** prod (jachammer.ai host allowlist ∪ `environment='prod'`) · PostHog project 425465

> Method: every query filters the exact UTC window and the prod environment filter used by the
> JacHammer analytics dashboard. Per-turn cost = server-emitted `ai_generation_metered` (real litellm $).
> "anon:xxxxxxxx" = a device that never identified (guest browsing). Person `plan` is the *current* value.

---

## 1. Activity timeline (30-min buckets)

| Bucket (UTC) | Active users | Signups | AI turns | Projects | Deploys OK | AI cost $ |
|---|---|---|---|---|---|---|
| 2026-07-26 17:00:00 | 17 | 2 | 1 | 1 | 0 |  |
| 2026-07-26 17:30:00 | 30 | 6 | 6 | 2 | 1 | 5.18 |
| 2026-07-26 18:00:00 | 69 | 20 | 12 | 6 | 0 | 6.75 |
| 2026-07-26 18:30:00 | 45 | 8 | 5 | 2 | 0 | 10.69 |
| 2026-07-26 19:00:00 | 63 | 14 | 16 | 7 | 0 | 13.37 |
| 2026-07-26 19:30:00 | 37 | 4 | 32 | 2 | 0 | 16.27 |
| 2026-07-26 20:00:00 | 37 | 5 | 33 | 6 | 0 | 18.12 |
| 2026-07-26 20:30:00 | 43 | 5 | 32 | 3 | 2 | 33.07 |
| 2026-07-26 21:00:00 | 41 | 5 | 20 | 4 | 5 | 27.95 |
| 2026-07-26 21:30:00 | 43 | 4 | 38 | 3 | 0 | 21.26 |
| 2026-07-26 22:00:00 | 41 | 3 | 17 | 1 | 3 | 27.82 |
| 2026-07-26 22:30:00 | 41 | 3 | 28 | 3 | 3 | 57.57 |
| 2026-07-26 23:00:00 | 36 | 1 | 22 | 0 | 4 | 43.31 |
| 2026-07-26 23:30:00 | 34 | 3 | 13 | 0 | 2 | 42.52 |
| 2026-07-27 00:00:00 | 51 | 8 | 22 | 0 | 6 | 27.9 |
| 2026-07-27 00:30:00 | 47 | 4 | 18 | 0 | 6 | 39.95 |
| 2026-07-27 01:00:00 | 43 | 5 | 15 | 1 | 5 | 56.39 |
| 2026-07-27 01:30:00 | 60 | 10 | 20 | 2 | 9 | 48.28 |
| 2026-07-27 02:00:00 | 63 | 2 | 16 | 4 | 11 | 26.12 |
| 2026-07-27 02:30:00 | 37 | 0 | 7 | 1 | 5 | 4.12 |
| 2026-07-27 03:00:00 | 12 | 0 | 0 | 0 | 1 |  |

Peak signup wave: 18:00–19:30 (42 signups). Peak build+spend: 20:30–00:00. Deploys clustered in the
final 3 hours — classic hackathon shape (build first, ship at the deadline).

---

## 2. Funnel

| Stage | Users |
|---|---|
| Visited (any prod event) | 357 |
| Signed up (new) | 112 |
| Opened the IDE | 79 |
| Sent ≥1 AI message | 55 |
| Created a project | 31 |
| Got a preview ready | 62 |
| Attempted a deploy | 25 |
| Succeeded a deploy | 17 |
| Completed an upgrade | 51 |

---

## 3. Signups & sign-ins

**112 new signups.** Method: google 68 · github 40 · password 3 · unknown 1. Trigger: direct 90 · guest_locked_feature 13 · dashboard_prompt 9
**8 returning users** signed in without a new signup.

### All hackathon signups (chronological)

| Time (UTC) | Email | Name | Method | Trigger |
|---|---|---|---|---|
| 07-26 17:22 | nihar.manchikalapudi@gmail.com | Nihar Manchikalapudi | github | direct |
| 07-26 17:23 | sohamjani8@gmail.com | sohamtjani | github | dashboard_prompt |
| 07-26 17:37 | misha@mypipdev.com | Misha Stastna | google | direct |
| 07-26 17:43 | lipeyton2006@gmail.com | Peyton Li | google | guest_locked_feature |
| 07-26 17:48 | noriaki@uni.minerva.edu | Noriaki Kishida | google | direct |
| 07-26 17:50 | sahilnale@icloud.com | sahilnale | github | direct |
| 07-26 17:55 | mborgiottitulane@gmail.com | Max Borgiotti | google | direct |
| 07-26 17:55 | georgeceja08@gmail.com | George Ceja | google | direct |
| 07-26 18:00 | mannycristino@gmail.com | manny-cr | github | direct |
| 07-26 18:00 | justin-kang@berkeley.edu | Justin Kang | google | direct |
| 07-26 18:01 | amberkaurtoor@gmail.com | Amber Toor | google | dashboard_prompt |
| 07-26 18:01 | manidweepsharma1801@gmail.com | manidweep sharma | google | direct |
| 07-26 18:02 | fkw155@mun.ca | frankie-eight-days | github | direct |
| 07-26 18:06 | krishnadua.official@gmail.com | Krishna Dua | google | direct |
| 07-26 18:07 | likhith11ramesh@gmail.com | Likhith Ramesha | google | direct |
| 07-26 18:08 | Ryanandnoahlee@gmail.com | comp-Ryan | github | dashboard_prompt |
| 07-26 18:09 | motdharer1999@gmail.com | Rohit Vaishali Motdhare | google | direct |
| 07-26 18:09 | arshmeetsodhi@gmail.com | Arshmeet Sodhi | google | direct |
| 07-26 18:09 | mrend1@jh.edu | mercedesrend | github | direct |
| 07-26 18:09 |  |  | google | direct |
| 07-26 18:13 | stevenyang.dev@gmail.com | syang0624 | github | direct |
| 07-26 18:15 | gabjenkinson@gmail.com | Gabriel Jenkinson | google | direct |
| 07-26 18:16 | atharavhedage@gmail.com | Atharav Hedage | google | direct |
| 07-26 18:16 | kewinszlezingier@gmail.com | Kewin Szlezingier | google | dashboard_prompt |
| 07-26 18:20 | jacob.a.quion@gmail.com | JacobQuion | github | direct |
| 07-26 18:21 | ewanjedlic@gmail.com | uwin-13 | github | direct |
| 07-26 18:23 | lmntrixgiga@gmail.com | Lmntrix | google | direct |
| 07-26 18:23 | chengreric@gmail.com | 陈冠荣 | google | direct |
| 07-26 18:34 | enochfyw@gmail.com | eyfung | github | direct |
| 07-26 18:39 | aneeshpradhan@acm.org | aneesh-pradhan | github | dashboard_prompt |
| 07-26 18:42 | kakanisnehil@gmail.com | snek152 | github | direct |
| 07-26 18:43 | 142857tom@gmail.com | Shockwave Thomas | google | direct |
| 07-26 18:44 | kshitijkumar3@gmail.com | Kshitij Kumar | google | direct |
| 07-26 18:44 | amyhsieh3730@gmail.com | amyxhsieh | github | direct |
| 07-26 18:46 |  |  | google | direct |
| 07-26 18:53 | yujiwork@outlook.com | yojijoestar | github | direct |
| 07-26 19:04 | schan119@calpoly.edu | samsonchang2028 | github | direct |
| 07-26 19:07 | kirthanamedha@gmail.com | kmn01 | github | direct |
| 07-26 19:16 | tiwari.aadi123@gmail.com | Aadi Tiwari | google | direct |
| 07-26 19:17 |  |  | password | dashboard_prompt |
| 07-26 19:17 | wanzelin007@gmail.com | Zelin Wan | google | direct |
| 07-26 19:17 | abhinavmgarg@gmail.com | Abhinav Garg | google | direct |
| 07-26 19:17 | speedytechus@gmail.com | Speedy Tech | google | direct |
| 07-26 19:22 | nagatarunmoturi@gmail.com | Tarun Moturi | google | direct |
| 07-26 19:23 | ybhatia2@wisc.edu | ybhatia10088 | github | direct |
| 07-26 19:23 | toledosean@gmail.com | Sean T | google | direct |
| 07-26 19:24 | Carol10051113@gmail.com | Carol929 | github | direct |
| 07-26 19:24 | owin@owinrojas.com | Owin Rojas | google | dashboard_prompt |
| 07-26 19:25 | kho@uni.minerva.edu | Carl Vincent Kho | google | direct |
| 07-26 19:29 | bnisevich@gmail.com | benjamin nisevich | google | direct |
| 07-26 19:30 | yugtmath@umich.edu | yugt | github | direct |
| 07-26 19:34 | sahasrakokkula77@gmail.com | K-SAHASRA | github | direct |
| 07-26 19:37 |  | krrithik | password | direct |
| 07-26 19:48 |  | Rosekr1 | password | direct |
| 07-26 20:03 | jsshekhtm@gmail.com | Julian Shekhtmeyster | google | direct |
| 07-26 20:07 | scott.simenel@gmail.com | Scott Simenel | google | direct |
| 07-26 20:15 | philipnisevich@gmail.com | Philip Nisevich | google | direct |
| 07-26 20:27 | umangshankar10@gmail.com | Umang3211 | github | dashboard_prompt |
| 07-26 20:28 | benjinisevich2@gmail.com | benji nisevich2 | google | direct |
| 07-26 20:32 | noliversauce@gmail.com | nathansso | github | direct |
| 07-26 20:32 | ryanxu240@gmail.com | rxu240 | github | direct |
| 07-26 20:56 | samrocksnature@gmail.com | samrocksnature | github | direct |
| 07-26 20:57 | kalenakkdai@gmail.com | Kalena D. | google | direct |
| 07-26 20:59 | vivekajayjariwala@gmail.com | vivekajayjariwala | github | direct |
| 07-26 21:00 | connorlai702@gmail.com | Connor Lai | google | direct |
| 07-26 21:03 | krishna.mdesai03@gmail.com | Krishna Mineshkumar Desai | google | direct |
| 07-26 21:06 | stepodkelly@gmail.com | Stephen Kelly | google | direct |
| 07-26 21:15 | arunachalamk058@gmail.com | Arunachalam Kasi | google | direct |
| 07-26 21:25 | mailjohnsonchris@gmail.com | Chris Johnson | google | direct |
| 07-26 21:30 | umarpadela@gmail.com | Umar Padela | google | direct |
| 07-26 21:37 | bhaladharesaniya02@gmail.com | Saniya | google | direct |
| 07-26 21:47 | kvenugop@usc.edu | Karthikvenugopal | github | direct |
| 07-26 21:53 | clai74@mail.ccsf.edu | Chineseman Lai | google | direct |
| 07-26 22:00 | satwikug@gmail.com | satwikug25 | github | direct |
| 07-26 22:03 | chaitanya11203@gmail.com | Chaitanya Prasad | google | direct |
| 07-26 22:12 | marambio.sebastian@gmail.com | brainforwarding | github | direct |
| 07-26 22:42 | cajuliawan@gmail.com | Julia Wan | google | dashboard_prompt |
| 07-26 22:43 | lee.anastasia.y@gmail.com | alee51 | github | direct |
| 07-26 22:51 | neilshah684@gmail.com | Neil Shah | google | guest_locked_feature |
| 07-26 23:20 | kshitijatus@gmail.com | Kshitij | google | direct |
| 07-26 23:45 | jbrendanfay@gmail.com | Brendan Fay | google | direct |
| 07-26 23:48 | harshjannawar14@gmail.com | harsh jannawar | google | direct |
| 07-26 23:49 | saisathvikgorle@gmail.com | Sathvik Gorle | google | direct |
| 07-27 00:00 |  |  | google | direct |
| 07-27 00:04 | shaurya2007.rana@gmail.com | Solaris696 | github | guest_locked_feature |
| 07-27 00:06 | navelan.muthusamy@gmail.com | Navelan Muthusamy | google | guest_locked_feature |
| 07-27 00:17 | jczhang223@gmail.com | Jaden Zhang | google | direct |
| 07-27 00:25 | dejiazhu@umich.edu | Edgar Zhu | google | direct |
| 07-27 00:27 | visheshv05@gmail.com | Vishesh Verma | google | guest_locked_feature |
| 07-27 00:28 | wuyi010507@gmail.com | wuyi010507-source | github | direct |
| 07-27 00:28 | aakashryback@gmail.com | vidiyala99 | github | direct |
| 07-27 00:49 | siddharthsaibarla@gmail.com | Siddharth Barla | google | guest_locked_feature |
| 07-27 00:52 | ghifari.arsa@gmail.com | GhifariArsa | unknown | direct |
| 07-27 00:54 | phongct1105@gmail.com | PhongCT1105 | github | direct |
| 07-27 00:59 | cezeoke@umich.edu | Chuka Ezeoke | google | guest_locked_feature |
| 07-27 01:08 | kishore.hkrish@gmail.com | Kishore Harikrishnan | google | direct |
| 07-27 01:12 |  |  | google | direct |
| 07-27 01:20 | alara.martin@gmail.com | alaramartin | github | direct |
| 07-27 01:25 | zsslufe9@gmail.com | tom | google | direct |
| 07-27 01:29 |  |  | github | guest_locked_feature |
| 07-27 01:42 | a20200796@pucp.edu.pe | alvax64 | github | direct |
| 07-27 01:44 | harshith.mannaru@manabadi.siliconandhra.org | Harshith Sai Mannaru | google | guest_locked_feature |
| 07-27 01:44 | gonzalo.galvezc@pucp.edu.pe | Duvet05 | github | direct |
| 07-27 01:46 | neil_shah@my.cuesta.edu | Neil Shah | google | direct |
| 07-27 01:47 | hussainmahuvawala1711@gmail.com | hmahuvawala | github | guest_locked_feature |
| 07-27 01:48 | vivaansrivastava12@gmail.com | Yba | google | direct |
| 07-27 01:50 | praniil.nagaraj@gmail.com | Praniil Nagaraj | google | direct |
| 07-27 01:50 | samanyu.aiprojects@gmail.com | Samanyu | google | guest_locked_feature |
| 07-27 01:53 | walterchen.ca@gmail.com | Walter Chen | google | direct |
| 07-27 01:59 | ayaan.chawla@gmail.com | Ayaan C | google | guest_locked_feature |
| 07-27 02:12 | Matthew.you.2520@gmail.com | NonOxC | github | direct |
| 07-27 02:15 | gulianimanit@gmail.com | Manit Guliani | google | guest_locked_feature |

---

## 4. Projects created — 48 total

**How users started:** **prompt** 35 · **import** 5 · **template** 4 · **folder_upload** 4
(Template detail: fullstack-auth×2, empty×2)

| Time (UTC) | User | Source | Template / import kind |
|---|---|---|---|
| 07-26 17:24 | sohamjani8@gmail.com | prompt | empty |
| 07-26 17:41 | misha@mypipdev.com | prompt | empty |
| 07-26 17:51 | sahilnale@icloud.com | template | fullstack-auth |
| 07-26 18:01 | amberkaurtoor@gmail.com | prompt | empty |
| 07-26 18:06 | manidweepsharma1801@gmail.com | prompt | empty |
| 07-26 18:08 | Ryanandnoahlee@gmail.com | prompt | empty |
| 07-26 18:16 | kewinszlezingier@gmail.com | prompt | empty |
| 07-26 18:21 | jacob.a.quion@gmail.com | prompt | empty |
| 07-26 18:22 | manidweepsharma1801@gmail.com | template | empty |
| 07-26 18:40 | aneeshpradhan@acm.org | prompt | empty |
| 07-26 18:43 | kakanisnehil@gmail.com | prompt | empty |
| 07-26 19:03 | kshitijkumar3@gmail.com | prompt | empty |
| 07-26 19:04 | schan119@calpoly.edu | prompt | empty |
| 07-26 19:13 | yujiwork@outlook.com | prompt | empty |
| 07-26 19:18 | likhith11ramesh@gmail.com | prompt | empty |
| 07-26 19:25 | owin@owinrojas.com | prompt | empty |
| 07-26 19:25 | toledosean@gmail.com | prompt | empty |
| 07-26 19:26 | justin-kang@berkeley.edu | import | file |
| 07-26 19:32 | owin@owinrojas.com | template | fullstack-auth |
| 07-26 19:48 | enochfyw@gmail.com | prompt | empty |
| 07-26 20:00 | sahasrakokkula77@gmail.com | prompt | empty |
| 07-26 20:02 | sahasrakokkula77@gmail.com | prompt | empty |
| 07-26 20:06 | chengreric@gmail.com | template | empty |
| 07-26 20:12 | toledosean@gmail.com | prompt | empty |
| 07-26 20:14 | amyhsieh3730@gmail.com | prompt | empty |
| 07-26 20:17 | mp@gmail.com | prompt | empty |
| 07-26 20:32 | umangshankar10@gmail.com | prompt | empty |
| 07-26 20:47 | toledosean@gmail.com | prompt | empty |
| 07-26 20:59 | owin@owinrojas.com | prompt | empty |
| 07-26 21:00 | toledosean@gmail.com | prompt | empty |
| 07-26 21:17 | anon:Rosekr1 | prompt | empty |
| 07-26 21:19 | nagatarunmoturi@gmail.com | prompt | empty |
| 07-26 21:28 | anon:ea626e57 | prompt | empty |
| 07-26 21:31 | mp@gmail.com | prompt | empty |
| 07-26 21:43 | stepodkelly@gmail.com | prompt | empty |
| 07-26 21:49 | toledosean@gmail.com | prompt | empty |
| 07-26 22:21 | nagatarunmoturi@gmail.com | prompt | empty |
| 07-26 22:42 | cajuliawan@gmail.com | prompt | empty |
| 07-26 22:47 | cajuliawan@gmail.com | prompt | empty |
| 07-26 22:56 | tiwari.aadi123@gmail.com | prompt | empty |
| 07-27 01:26 | cezeoke@umich.edu | import | file |
| 07-27 01:36 | cezeoke@umich.edu | import | file |
| 07-27 01:38 | noriaki@uni.minerva.edu | folder_upload |  |
| 07-27 02:00 | noriaki@uni.minerva.edu | folder_upload |  |
| 07-27 02:10 | noriaki@uni.minerva.edu | folder_upload |  |
| 07-27 02:11 | cezeoke@umich.edu | import | file |
| 07-27 02:26 | noriaki@uni.minerva.edu | folder_upload |  |
| 07-27 02:41 | cezeoke@umich.edu | import | file |

> `project_created` does not carry `project_id`; per-project cost below joins on the `project_id`
> stamped on AI/preview events.

---

## 5. AI usage

- **373 turns sent** by 55 users in 76 conversations;
  302 completed, 52 failed, 30 user-aborted.
- Task mix: other 140 · debug 106 · explain 69 · generate 51 · test 5 · document 2
- Preview latency: p50 **1.2s** (warm) · p90 **123.2s** (cold starts) · avg 36.0s over 315 previews.

### Most active AI users

| User | Turns sent | Completed | Failed | Convs | Projects | Cost $ |
|---|---|---|---|---|---|---|
| justin-kang@berkeley.edu | 78 | 69 | 12 | 3 | 4 | 157.85 |
| toledosean@gmail.com | 24 | 23 | 1 | 5 | 5 | 29.69 |
| likhith11ramesh@gmail.com | 21 | 4 | 17 | 1 | 1 | 0.68 |
| benjinisevich2@gmail.com | 17 | 12 | 5 | 5 | 4 | 7.89 |
| anon:ea626e57 | 17 | 13 | 6 | 1 | 1 | 35.19 |
| nagatarunmoturi@gmail.com | 16 | 16 | 0 | 2 | 2 | 6.70 |
| sahasrakokkula77@gmail.com | 14 | 14 | 0 | 1 | 1 | 12.17 |
| jacob.a.quion@gmail.com | 13 | 12 | 0 | 1 | 1 | 15.21 |
| kshitijkumar3@gmail.com | 11 | 11 | 0 | 1 | 1 | 14.10 |
| anon:Rosekr1 | 11 | 11 | 0 | 1 | 1 | 4.49 |
| kshitijatus@gmail.com | 10 | 10 | 0 | 1 | 1 | 13.98 |
| mborgiottitulane@gmail.com | 9 | 1 | 3 | 1 | 1 | 4.81 |
| stevenyang.dev@gmail.com | 8 | 8 | 1 | 1 | 1 | 72.45 |
| enochfyw@gmail.com | 7 | 7 | 0 | 1 | 2 | 10.53 |
| phongct1105@gmail.com | 6 | 5 | 0 | 1 | 1 | 4.12 |
| sahilnale@icloud.com | 6 | 5 | 0 | 2 | 1 | 1.11 |
| manidweepsharma1801@gmail.com | 6 | 6 | 0 | 2 | 2 | 2.41 |
| owin@owinrojas.com | 6 | 5 | 2 | 3 | 3 | 7.58 |
| rishabh.rb@icloud.com | 5 | 5 | 0 | 1 | 1 | 3.12 |
| mp@gmail.com | 5 | 1 | 4 | 2 | 2 | 0.03 |

---

## 6. Cost breakdown — **$526.62** metered

### By model

| Model | Runs | Users | Total $ | Avg $ | Max $ | BYOK runs | BYOK $ |
|---|---|---|---|---|---|---|---|
| claude-sonnet-4-6 | 210 | 50 | 229.4527 | 1.09263 | 9.0239 | 0 |  |
| claude-opus-4-6 | 63 | 7 | 194.5823 | 3.08861 | 25.9825 | 0 |  |
|  | 19 | 12 | 98.3277 | 5.17514 | 20.0071 | 0 |  |
| gpt-5.4 | 2 | 1 | 3.1781 | 1.58903 | 1.7386 | 0 |  |
| gpt-5.2 | 6 | 2 | 0.7694 | 0.12823 | 0.2298 | 0 |  |
| claude-opus-4-5-20251101 | 1 | 1 | 0.3051 | 0.30508 | 0.3051 | 1 | 0.3051 |

> ⚠ The blank-model row is $98.33 of real spend across 19 runs
> (12 users) where `model` arrived empty — instrumentation gap to fix in
> `_record_user_cost_entry`.

### By user × model (top 25 spenders — full matrix in `data/cost_by_user_model.csv`)

| User | Runs | Total $ | claude-sonnet-4-6 | claude-opus-4-6 | (blank) | gpt-5.4 | gpt-5.2 | claude-opus-4-5-20251101 |
|---|---|---|---|---|---|---|---|---|
| justin-kang@berkeley.edu | 64 | 157.8541 | 8.8999 | 109.0606 | 39.8935 |  |  |  |
| stevenyang.dev@gmail.com | 7 | 72.4479 | 14.4675 | 37.9733 | 20.0071 |  |  |  |
| anon:ea626e57 | 6 | 35.1901 | 19.7645 |  | 15.4256 |  |  |  |
| toledosean@gmail.com | 23 | 29.6861 | 1.0125 | 26.1589 | 2.5147 |  |  |  |
| jacob.a.quion@gmail.com | 12 | 15.2094 | 11.6111 |  | 3.5983 |  |  |  |
| kshitijkumar3@gmail.com | 11 | 14.0953 | 10.8926 | 1.6428 | 1.5599 |  |  |  |
| kshitijatus@gmail.com | 10 | 13.9831 |  | 13.9831 |  |  |  |  |
| anon:knemavat | 10 | 12.8289 | 12.8289 |  |  |  |  |  |
| sahasrakokkula77@gmail.com | 12 | 12.1694 | 12.1694 |  |  |  |  |  |
| philipnisevich@gmail.com | 4 | 11.7631 | 11.7631 |  |  |  |  |  |
| umangshankar10@gmail.com | 3 | 10.5365 | 10.5365 |  |  |  |  |  |
| enochfyw@gmail.com | 7 | 10.5325 | 10.5325 |  |  |  |  |  |
| kakanisnehil@gmail.com | 2 | 8.2761 | 8.2761 |  |  |  |  |  |
| noriaki@uni.minerva.edu | 4 | 8.1042 | 8.1042 |  |  |  |  |  |
| benjinisevich2@gmail.com | 14 | 7.8918 | 7.8918 |  |  |  |  |  |
| owin@owinrojas.com | 3 | 7.5782 | 3.4893 | 4.089 |  |  |  |  |
| stepodkelly@gmail.com | 1 | 7.3752 |  |  | 7.3752 |  |  |  |
| amyhsieh3730@gmail.com | 2 | 6.9995 | 6.9995 |  |  |  |  |  |
| nagatarunmoturi@gmail.com | 16 | 6.6975 | 6.6975 |  |  |  |  |  |
| clai74@mail.ccsf.edu | 2 | 6.0836 | 6.0836 |  |  |  |  |  |
| mborgiottitulane@gmail.com | 2 | 4.8148 | 4.8148 |  |  |  |  |  |
| anon:Rosekr1 | 10 | 4.4899 | 4.4899 |  |  |  |  |  |
| kewinszlezingier@gmail.com | 1 | 4.2283 | 4.2283 |  |  |  |  |  |
| misha@mypipdev.com | 3 | 4.1992 | 4.1992 |  |  |  |  |  |
| phongct1105@gmail.com | 6 | 4.1172 | 2.0718 |  | 2.0454 |  |  |  |

### By project (top 20 — full list in `data/cost_by_project.csv`)

| Project id | Owner | Runs | Total $ | Models |
|---|---|---|---|---|
| 44090311-4bd8-4f29-9348-091c7ecb388f | justin-kang@berkeley.edu | 33 | 148.9541 | (blank), claude-opus-4-6 |
| 3296f689-9bf7-44b2-bb76-171ca01186a3 | stevenyang.dev@gmail.com | 7 | 72.4479 | (blank), claude-opus-4-6, claude-sonnet-4-6 |
| prj_b180bd849abe4731b391c1dd585be000 |  | 6 | 35.1901 | (blank), claude-sonnet-4-6 |
| prj_9408e7836d3240fcb14fa6ae0caa0453 | toledosean@gmail.com | 19 | 19.975 | (blank), claude-opus-4-6, claude-sonnet-4-6 |
| prj_07924aa5d8844a4c92ec1db23476ff4a | jacob.a.quion@gmail.com | 12 | 15.2094 | (blank), claude-sonnet-4-6 |
| prj_b88f4c0b585642c899688ce48603ea48 | kshitijkumar3@gmail.com | 11 | 14.0952 | (blank), claude-opus-4-6, claude-sonnet-4-6 |
| fe8b9d27-9f88-4952-bdab-74f6301cb298 | kshitijatus@gmail.com | 10 | 13.9831 | claude-opus-4-6 |
| prj_4a221e53ef884270ad1424fee9f41f90 | sahasrakokkula77@gmail.com | 12 | 12.1694 | claude-sonnet-4-6 |
| fa325ad8-92a1-460b-bebc-6e41d0744990 | philipnisevich@gmail.com | 4 | 11.7631 | claude-sonnet-4-6 |
| prj_4f409ce952ed458ebf2627aa06c44fad | enochfyw@gmail.com | 7 | 10.5325 | claude-sonnet-4-6 |
| prj_bfde8a2032ee4e6c9ea636a6afcadf2c | justin-kang@berkeley.edu | 31 | 8.8999 | claude-sonnet-4-6 |
| prj_154ea02e80f04b71877b98956e565c12 | kakanisnehil@gmail.com | 2 | 8.2761 | claude-sonnet-4-6 |
| 9f23a6c7-a167-4b13-aa92-58e43f20cb1d | noriaki@uni.minerva.edu | 4 | 8.1042 | claude-sonnet-4-6 |
| prj_d071db4af98d4fe1a789f8c1bb45b0e6 | umangshankar10@gmail.com | 2 | 7.4295 | claude-sonnet-4-6 |
| prj_7782ae176a0f4d33bbee7296d3956151 | stepodkelly@gmail.com | 1 | 7.3752 | (blank) |
| prj_ce4dd6df91864d219f2baa8910a1d9ea | toledosean@gmail.com | 1 | 7.337 | claude-opus-4-6 |
| prj_36eb9b5db1be4be39f04ac6563777c3c |  | 4 | 6.5363 | claude-sonnet-4-6 |
| 730ceb72-ce18-4665-aeb1-94ca18c2a89c | clai74@mail.ccsf.edu | 2 | 6.0836 | claude-sonnet-4-6 |
| prj_826a6397e8994cdf9b1284c5daf5d5ac | amyhsieh3730@gmail.com | 1 | 5.8299 | claude-sonnet-4-6 |
| aa8d4bef-a2f4-4f6d-8e63-8f3b68f7ac8e | benjinisevich2@gmail.com | 12 | 5.3748 | claude-sonnet-4-6 |

### BYOK vs platform keys

- **BYOK:** 1 run / $0.31 — likhith11ramesh@gmail.com
- **Platform (non-BYOK):** 300 runs / $526.31

Per-turn rows (timestamp, user, model, $, byok, project, run_id): `data/cost_per_turn.csv` (301 rows).

---

## 7. Deploys

| Kind | Clicks (users) | Succeeded (users) | Failed (users) |
|---|---|---|---|
| **Sandbox** | 70 (18) | **37 (11)** | 30 (13) |
| **Production** | 53 (15) | **26 (9)** | 10 (6) |

Status values on outcomes: production_failed:failed×10 · production_succeeded:running×26 · sandbox_failed:failed×30 · sandbox_succeeded:running×37
Deploy-upsell clicks (locked deploy → upgrade modal): 17 by 13 users.

### Per deployer — clicked/succeeded/failed

| User | Sandbox c/s/f | Production c/s/f | AI turns | Projects created |
|---|---|---|---|---|
| wanzelin007@gmail.com | 16/14/0 | 12/8/1 | 1 | 0 |
| benjinisevich2@gmail.com | 8/2/2 | 12/5/5 | 17 | 0 |
| sahilnale@icloud.com | 7/7/0 | 1/0/0 | 6 | 1 |
| kakanisnehil@gmail.com | 17/6/7 | 1/0/0 | 4 | 1 |
| a20200796@pucp.edu.pe | 1/1/1 | 9/4/0 | 0 | 0 |
| stevenyang.dev@gmail.com | 0/0/0 | 2/2/0 | 8 | 0 |
| rishabh.rb@icloud.com | 2/2/0 | 0/0/0 | 5 | 0 |
| noriaki@uni.minerva.edu | 0/0/0 | 3/2/0 | 4 | 4 |
| harshith.mannaru@manabadi.siliconandhra.org | 0/0/0 | 2/2/0 | 0 | 0 |
| justin-kang@berkeley.edu | 1/1/0 | 2/0/0 | 78 | 1 |
| noliversauce@gmail.com | 1/1/0 | 0/0/0 | 0 | 0 |
| enochfyw@gmail.com | 0/0/0 | 1/1/0 | 7 | 1 |
| cajuliawan@gmail.com | 0/0/0 | 3/1/1 | 2 | 2 |
| 142857tom@gmail.com | 1/1/0 | 0/0/0 | 3 | 0 |
| philipnisevich@gmail.com | 2/1/1 | 1/0/1 | 4 | 0 |
| bryanpham2024@gmail.com | 1/1/0 | 0/0/0 | 0 | 0 |
| anon:2ab5b433 | 0/0/0 | 1/1/0 | 0 | 0 |
| phongct1105@gmail.com | 4/0/2 | 0/0/0 | 6 | 0 |
| arshmeetsodhi@gmail.com | 1/0/0 | 0/0/0 | 4 | 0 |
| umangshankar10@gmail.com | 1/0/0 | 0/0/0 | 4 | 1 |
| bnisevich@gmail.com | 2/0/0 | 0/0/0 | 0 | 0 |
| tiwari.aadi123@gmail.com | 3/0/3 | 2/0/1 | 1 | 1 |
| kvenugop@usc.edu | 1/0/2 | 0/0/0 | 0 | 0 |
| abhinavmgarg@gmail.com | 0/0/0 | 1/0/1 | 0 | 0 |
| harshjannawar14@gmail.com | 1/0/2 | 0/0/0 | 2 | 0 |

### "Deploy-only" users (deploy activity, zero AI turns & zero projects in-window)

| User | Sandbox c/s/f | Production c/s/f |
|---|---|---|
| noliversauce@gmail.com | 1/1/0 | 0/0/0 |
| bnisevich@gmail.com | 2/0/0 | 0/0/0 |
| a20200796@pucp.edu.pe | 1/1/1 | 9/4/0 |
| bryanpham2024@gmail.com | 1/1/0 | 0/0/0 |
| anon:2ab5b433 | 0/0/0 | 1/1/0 |
| kvenugop@usc.edu | 1/0/2 | 0/0/0 |
| abhinavmgarg@gmail.com | 0/0/0 | 1/0/1 |
| harshith.mannaru@manabadi.siliconandhra.org | 0/0/0 | 2/2/0 |

---

## 8. GitHub

- **Connected successfully: 14 users** — atharavhedage@gmail.com, chengreric@gmail.com, enochfyw@gmail.com, jacob.a.quion@gmail.com, justin-kang@berkeley.edu, kakanisnehil@gmail.com, kshitijkumar3@gmail.com, kvenugop@usc.edu, noliversauce@gmail.com, noriaki@uni.minerva.edu, rishabh.rb@icloud.com, ryanxu240@gmail.com, sahilnale@icloud.com, umangshankar10@gmail.com
- Clicked but no success in-window: —
- Failures: jacob.a.quion@gmail.com (21:35), enochfyw@gmail.com (23:23), atharavhedage@gmail.com (01:38), atharavhedage@gmail.com (01:39), atharavhedage@gmail.com (01:39), atharavhedage@gmail.com (01:54)
- No `git_commit_*` events fired in the window (nobody used in-IDE git commit).

---

## 9. Upgrades & monetization

- Intent: **56 checkout clicks** by 47 users; 27 top-up clicks by 7 users.
- **Completed: 53 upgrades** by 51 users — **$1,135.00** total checkout value.
- Failed checkouts: 3 (anon:2ab5b433, enochfyw@gmail.com, jczhang223@gmail.com).

### Plan transitions

| Transition (interval) | Count | $ total |
|---|---|---|
| free → pro (month) | 32 | 800.00 |
| free → builder (month) | 19 | 285.00 |
| builder → pro (month) | 2 | 50.00 |

### Completed upgrades (chronological)

| Time (UTC) | User | From | To | Interval | $ | First upgrade |
|---|---|---|---|---|---|---|
| 07-26 19:15 | aneeshpradhan@acm.org | free | builder | month | 15.00 | true |
| 07-26 19:17 | justin-kang@berkeley.edu | free | pro | month | 25.00 | true |
| 07-26 19:19 | speedytechus@gmail.com | free | pro | month | 25.00 | true |
| 07-26 19:23 | jacob.a.quion@gmail.com | free | pro | month | 25.00 | true |
| 07-26 19:24 | tiwari.aadi123@gmail.com | free | builder | month | 15.00 | true |
| 07-26 19:24 | nagatarunmoturi@gmail.com | free | pro | month | 25.00 | true |
| 07-26 19:24 | abhinavmgarg@gmail.com | free | builder | month | 15.00 | true |
| 07-26 19:25 | toledosean@gmail.com | free | pro | month | 25.00 | true |
| 07-26 19:26 | kho@uni.minerva.edu | free | pro | month | 25.00 | true |
| 07-26 19:26 | owin@owinrojas.com | free | pro | month | 25.00 | true |
| 07-26 19:26 | enochfyw@gmail.com | free | pro | month | 25.00 | true |
| 07-26 19:27 | kakanisnehil@gmail.com | free | builder | month | 15.00 | true |
| 07-26 19:28 | stevenyang.dev@gmail.com | free | pro | month | 25.00 | true |
| 07-26 19:29 | noriaki@uni.minerva.edu | free | pro | month | 25.00 | true |
| 07-26 19:29 | bnisevich@gmail.com | free | builder | month | 15.00 | true |
| 07-26 19:38 | anon:krrithik | free | pro | month | 25.00 | true |
| 07-26 19:39 | kshitijkumar3@gmail.com | free | pro | month | 25.00 | true |
| 07-26 19:49 | anon:Rosekr1 | free | builder | month | 15.00 | true |
| 07-26 19:49 | anon:Rosekr1 | builder | pro | month | 25.00 | false |
| 07-26 20:01 | manidweepsharma1801@gmail.com | free | pro | month | 25.00 | true |
| 07-26 20:01 | sahasrakokkula77@gmail.com | free | pro | month | 25.00 | true |
| 07-26 20:02 | amyhsieh3730@gmail.com | free | pro | month | 25.00 | true |
| 07-26 20:04 | wanzelin007@gmail.com | free | pro | month | 25.00 | true |
| 07-26 20:16 | sahilnale@icloud.com | free | builder | month | 15.00 | true |
| 07-26 20:21 | kirthanamedha@gmail.com | free | pro | month | 25.00 | true |
| 07-26 20:22 | ybhatia2@wisc.edu | free | pro | month | 25.00 | true |
| 07-26 20:34 | ryanxu240@gmail.com | free | pro | month | 25.00 | true |
| 07-26 20:35 | benjinisevich2@gmail.com | free | builder | month | 15.00 | true |
| 07-26 20:49 | philipnisevich@gmail.com | free | builder | month | 15.00 | true |
| 07-26 20:59 | kalenakkdai@gmail.com | free | pro | month | 25.00 | true |
| 07-26 21:04 | connorlai702@gmail.com | free | pro | month | 25.00 | true |
| 07-26 21:15 | umangshankar10@gmail.com | free | pro | month | 25.00 | true |
| 07-26 21:34 | umarpadela@gmail.com | free | pro | month | 25.00 | true |
| 07-26 21:38 | bhaladharesaniya02@gmail.com | free | pro | month | 25.00 | true |
| 07-26 21:52 | anon:ea626e57 | free | builder | month | 15.00 | true |
| 07-26 22:11 | chaitanya11203@gmail.com | free | pro | month | 25.00 | true |
| 07-26 22:51 | lee.anastasia.y@gmail.com | free | pro | month | 25.00 | true |
| 07-26 22:57 | neilshah684@gmail.com | free | builder | month | 15.00 | true |
| 07-26 23:00 | anon:knemavat | free | builder | month | 15.00 | true |
| 07-26 23:22 | kshitijatus@gmail.com | free | pro | month | 25.00 | true |
| 07-26 23:49 | harshjannawar14@gmail.com | free | pro | month | 25.00 | true |
| 07-27 00:18 | jczhang223@gmail.com | free | pro | month | 25.00 | true |
| 07-27 00:24 | schan119@calpoly.edu | free | pro | month | 25.00 | true |
| 07-27 00:27 | anon:2ab5b433 | free | builder | month | 15.00 | true |
| 07-27 00:49 | anon:knemavat | builder | pro | month | 25.00 | false |
| 07-27 01:12 | cajuliawan@gmail.com | free | builder | month | 15.00 | true |
| 07-27 01:25 | cezeoke@umich.edu | free | builder | month | 15.00 | true |
| 07-27 01:26 | zsslufe9@gmail.com | free | pro | month | 25.00 | true |
| 07-27 01:48 | a20200796@pucp.edu.pe | free | builder | month | 15.00 | true |
| 07-27 01:51 | praniil.nagaraj@gmail.com | free | pro | month | 25.00 | true |
| 07-27 01:51 | harshith.mannaru@manabadi.siliconandhra.org | free | builder | month | 15.00 | true |
| 07-27 01:57 | mannycristino@gmail.com | free | builder | month | 15.00 | true |
| 07-27 02:26 | neil_shah@my.cuesta.edu | free | builder | month | 15.00 | true |

---

## 10. Issues & friction — who hit what

### AI failure reasons

| Reason | Count | Users |
|---|---|---|
| A turn is already in progress for this project; wait for it to finish. | 19 | anon:ea626e57, arshmeetsodhi@gmail.com, justin-kang@berkeley.edu, mborgiottitulane@gmail.com, owin@owinrojas.com, stevenyang.dev@gmail.com |
| litellm.BadRequestError: AnthropicException - b'{"type":"error","error":{"type": | 14 | likhith11ramesh@gmail.com, mp@gmail.com |
| This model is no longer in your selected models (Dashboard → AI Models). Pick an | 4 | likhith11ramesh@gmail.com |
| Agent did not respond. Please try again. | 4 | anon:ea626e57, benjinisevich2@gmail.com, justin-kang@berkeley.edu, toledosean@gmail.com |
| litellm.APIError: APIError: OpenrouterException - {"error":{"message":"This requ | 3 | mp@gmail.com |
| TypeError: Failed to fetch | 3 | benjinisevich2@gmail.com |
| Exception: Walker ai_chat failed: <html>
<head><title>504 Gateway Time-out</tit | 2 | justin-kang@berkeley.edu |
| Connection lost. Please try again. | 1 | mborgiottitulane@gmail.com |
| Tool.make_finish_tool.<locals>.finish_tool() missing 1 required positional argum | 1 | justin-kang@berkeley.edu |
| This build was interrupted by a server restart. Files written so far are saved,  | 1 | benjinisevich2@gmail.com |

### Quota blocks
6 users hit `ai_message_blocked_quota`: anon:ea626e57, jacob.a.quion@gmail.com, kakanisnehil@gmail.com, kewinszlezingier@gmail.com, mborgiottitulane@gmail.com, praniil.nagaraj@gmail.com

### Preview failures
| Time | User | Reason | Phase |
|---|---|---|---|
| 2026-07-26 22:28:42.200000 | sahilnale@icloud.com | max_retries | sandbox_gone |
| 2026-07-27 00:01:57.651000 | harshjannawar14@gmail.com | max_retries | sandbox_gone |
| 2026-07-27 00:32:14.841000 | wanzelin007@gmail.com | http_start_failed | http_response |
| 2026-07-27 00:32:44.071000 | wanzelin007@gmail.com | http_start_failed | http_response |
| 2026-07-27 01:12:23.254000 | arshmeetsodhi@gmail.com | TypeError: Load failed | http_response |
| 2026-07-27 01:14:17.442000 | arshmeetsodhi@gmail.com | http_start_failed | http_response |
| 2026-07-27 01:14:56.742000 | arshmeetsodhi@gmail.com | http_start_failed | http_response |
| 2026-07-27 01:20:03.896000 | phongct1105@gmail.com | http_start_failed | http_response |
| 2026-07-27 01:21:00.193000 | phongct1105@gmail.com | Exception: Walker preview_control failed: <html>
<head><title>504 Gateway Time-out</title></head>
<body>
<center><h1>504 Gateway Time-out</h1></center>
</body>
</html>
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
 | http_response |
| 2026-07-27 01:23:28.688000 | wanzelin007@gmail.com | http_start_failed | http_response |
| 2026-07-27 01:26:34.132000 | cajuliawan@gmail.com | http_start_failed | http_response |
| 2026-07-27 01:26:59.717000 | cajuliawan@gmail.com | TypeError: Failed to fetch | http_response |
| 2026-07-27 01:26:59.718000 | cajuliawan@gmail.com | TypeError: Failed to fetch | http_response |
| 2026-07-27 01:34:06.577000 | samrocksnature@gmail.com | http_start_failed | http_response |
| 2026-07-27 01:34:40.478000 | phongct1105@gmail.com | http_start_failed | http_response |
| 2026-07-27 01:36:45.864000 | cajuliawan@gmail.com | http_start_failed | http_response |
| 2026-07-27 01:37:52.231000 | visheshv05@gmail.com | http_start_failed | http_response |
| 2026-07-27 01:43:01.278000 | atharavhedage@gmail.com | http_start_failed | http_response |
| 2026-07-27 01:45:39.628000 | stevenyang.dev@gmail.com | Exception: Walker preview_control failed: <html>
<head><title>504 Gateway Time-out</title></head>
<body>
<center><h1>504 Gateway Time-out</h1></center>
</body>
</html>
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
<!-- a padding to disable MSIE and Chrome friendly error page -->
 | http_response |
| 2026-07-27 01:45:42.892000 | stevenyang.dev@gmail.com | http_start_failed | http_response |
| 2026-07-27 02:01:27.713000 | justin-kang@berkeley.edu | TypeError: Failed to fetch | http_response |
| 2026-07-27 02:02:40.089000 | kshitijatus@gmail.com | Exception: Walker preview_control failed: <html>
<head><title>504 Gateway Time-out</title></head>
<body>
<center><h1>504 Gateway Time-out</h1></center>
</body>
</html>
 | http_response |

### Per-user issue log (all users who hit anything)

| User | Issues (event×count) |
|---|---|
| justin-kang@berkeley.edu | failed×12 · ai_user_aborted×6 · preview_failed×1 |
| likhith11ramesh@gmail.com | failed×17 |
| anon:ea626e57 | blocked_quota×1 · failed×6 · ai_user_aborted×7 |
| mborgiottitulane@gmail.com | blocked_quota×5 · failed×3 |
| benjinisevich2@gmail.com | failed×5 · ai_user_aborted×1 |
| arshmeetsodhi@gmail.com | failed×1 · ai_user_aborted×1 · preview_failed×3 |
| owin@owinrojas.com | failed×2 · ai_user_aborted×2 |
| mp@gmail.com | failed×4 |
| stevenyang.dev@gmail.com | failed×1 · ai_user_aborted×1 · preview_failed×2 |
| cajuliawan@gmail.com | preview_failed×4 |
| praniil.nagaraj@gmail.com | blocked_quota×3 · ai_user_aborted×1 |
| wanzelin007@gmail.com | preview_failed×3 |
| phongct1105@gmail.com | preview_failed×3 |
| sahilnale@icloud.com | ai_user_aborted×1 · preview_failed×1 |
| kewinszlezingier@gmail.com | blocked_quota×2 |
| kakanisnehil@gmail.com | blocked_quota×2 |
| sahasrakokkula77@gmail.com | ai_user_aborted×2 |
| toledosean@gmail.com | failed×1 · ai_user_aborted×1 |
| aneeshpradhan@acm.org | ai_user_aborted×1 |
| jacob.a.quion@gmail.com | blocked_quota×1 |
| schan119@calpoly.edu | ai_user_aborted×1 |
| yujiwork@outlook.com | ai_user_aborted×1 |
| chengreric@gmail.com | ai_user_aborted×1 |
| anon:Rosekr1 | ai_user_aborted×1 |
| stepodkelly@gmail.com | ai_user_aborted×1 |
| rishabh.rb@icloud.com | ai_user_aborted×1 |
| harshjannawar14@gmail.com | preview_failed×1 |
| samrocksnature@gmail.com | preview_failed×1 |
| visheshv05@gmail.com | preview_failed×1 |
| atharavhedage@gmail.com | preview_failed×1 |
| kshitijatus@gmail.com | preview_failed×1 |

> No `$exception` (JS error) events landed in the window, and no `project_creation_failed` fired.

---

## 11. Method & caveats

- **Window:** `timestamp >= '2026-07-26 17:00:00' AND < '2026-07-27 00:30:00'` — PostHog project TZ is UTC (verified).
- **Env filter:** `environment='prod' OR $host IN (jachammer.ai, www.jachammer.ai, jac-builder.jaseci.org)` on every query.
- **Cost** = `ai_generation_metered.cost_usd` (server-emitted litellm metered $; platform's real spend). BYOK runs are the user's own key — their `cost_usd` is what the user's key was billed, not platform spend.
- **Per-turn** = one `ai_generation_metered` row per generation run; `ai_message_completed` corroborates model/turn threading.
- `person.properties.plan/email` are **current** person values (post-window). `anon:` users never identified (guest traffic).
- `project_created` lacks `project_id` → project cost table joins on ids from AI/preview events; projects with zero AI runs don't appear in the cost table.
- 19 metered runs have empty `model` ($98.33) — fix in jac-ide `_record_user_cost_entry`.

### Files
| File | Contents |
|---|---|
| `SUMMARY.md` | Executive summary |
| `REPORT.md` | This report |
| `data/users_activity.csv` | Full per-user rollup (357 rows, every counter) |
| `data/signups.csv` · `data/projects_created.csv` | Row-level signups / projects |
| `data/cost_per_turn.csv` | 301 per-turn cost rows (user, model, $, byok, project, run) |
| `data/cost_by_user_model.csv` · `data/cost_by_project.csv` | Cost matrices |
| `data/upgrades_and_topups.csv` · `data/deploy_events.csv` · `data/github_events.csv` · `data/issue_events.csv` | Row-level detail |
