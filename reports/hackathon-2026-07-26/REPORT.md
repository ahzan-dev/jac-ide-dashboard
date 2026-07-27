# JacHammer Hackathon — Full Report
**Window:** 2026-07-26 17:00 → 2026-07-27 00:30 UTC (7.5 h) · **Env:** prod (jachammer.ai host allowlist ∪ `environment='prod'`) · PostHog project 425465

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

Peak signup wave: 18:00–19:30 (42 signups). Peak build+spend: 20:30–00:00. Deploys clustered in the
final 3 hours — classic hackathon shape (build first, ship at the deadline).

---

## 2. Funnel

| Stage | Users |
|---|---|
| Visited (any prod event) | 283 |
| Signed up (new) | 91 |
| Opened the IDE | 59 |
| Sent ≥1 AI message | 43 |
| Created a project | 29 |
| Got a preview ready | 47 |
| Attempted a deploy | 10 |
| Succeeded a deploy | 6 |
| Completed an upgrade | 43 |

---

## 3. Signups & sign-ins

**91 new signups.** Method: google 55 · github 33 · password 3. Trigger: direct 77 · dashboard_prompt 9 · guest_locked_feature 5
**5 returning users** signed in without a new signup.

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

---

## 4. Projects created — 40 total

**How users started:** **prompt** 35 · **template** 4 · **import** 1
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

> `project_created` does not carry `project_id`; per-project cost below joins on the `project_id`
> stamped on AI/preview events.

---

## 5. AI usage

- **297 turns sent** by 43 users in 60 conversations;
  242 completed, 40 failed, 26 user-aborted.
- Task mix: other 110 · debug 80 · explain 58 · generate 42 · test 5 · document 2
- Preview latency: p50 **1.1s** (warm) · p90 **122.4s** (cold starts) · avg 31.6s over 220 previews.

### Most active AI users

| User | Turns sent | Completed | Failed | Convs | Projects | Cost $ |
|---|---|---|---|---|---|---|
| justin-kang@berkeley.edu | 57 | 53 | 6 | 2 | 3 | 95.21 |
| toledosean@gmail.com | 24 | 23 | 1 | 5 | 5 | 29.69 |
| likhith11ramesh@gmail.com | 21 | 4 | 17 | 1 | 1 | 0.68 |
| nagatarunmoturi@gmail.com | 16 | 16 | 0 | 2 | 2 | 6.70 |
| anon:ea626e57 | 15 | 10 | 6 | 1 | 1 | 26.70 |
| sahasrakokkula77@gmail.com | 14 | 14 | 0 | 1 | 1 | 12.17 |
| jacob.a.quion@gmail.com | 13 | 12 | 0 | 1 | 1 | 15.21 |
| kshitijkumar3@gmail.com | 11 | 11 | 0 | 1 | 1 | 14.10 |
| anon:Rosekr1 | 11 | 11 | 0 | 1 | 1 | 4.49 |
| mborgiottitulane@gmail.com | 9 | 1 | 3 | 1 | 1 | 4.81 |
| benjinisevich2@gmail.com | 7 | 7 | 0 | 4 | 4 | 5.23 |
| enochfyw@gmail.com | 7 | 7 | 0 | 1 | 2 | 10.53 |
| manidweepsharma1801@gmail.com | 6 | 6 | 0 | 2 | 2 | 2.41 |
| owin@owinrojas.com | 6 | 5 | 2 | 3 | 3 | 7.58 |
| stevenyang.dev@gmail.com | 5 | 5 | 1 | 1 | 1 | 18.62 |
| sahilnale@icloud.com | 5 | 4 | 0 | 2 | 1 | 0.18 |
| yujiwork@outlook.com | 5 | 5 | 0 | 1 | 1 | 4.00 |
| mp@gmail.com | 5 | 1 | 4 | 2 | 2 | 0.03 |
| kakanisnehil@gmail.com | 4 | 0 | 0 | 1 | 2 | 8.28 |
| philipnisevich@gmail.com | 4 | 4 | 0 | 1 | 1 | 11.76 |

---

## 6. Cost breakdown — **$351.76** metered

### By model

| Model | Runs | Users | Total $ | Avg $ | Max $ | BYOK runs | BYOK $ |
|---|---|---|---|---|---|---|---|
| claude-sonnet-4-6 | 172 | 39 | 198.1704 | 1.15215 | 9.0239 | 0 |  |
| claude-opus-4-6 | 38 | 6 | 102.7264 | 2.70333 | 25.9825 | 0 |  |
|  | 11 | 8 | 46.606 | 4.23691 | 10.6238 | 0 |  |
| gpt-5.4 | 2 | 1 | 3.1781 | 1.58903 | 1.7386 | 0 |  |
| gpt-5.2 | 6 | 2 | 0.7694 | 0.12823 | 0.2298 | 0 |  |
| claude-opus-4-5-20251101 | 1 | 1 | 0.3051 | 0.30508 | 0.3051 | 1 | 0.3051 |

> ⚠ The blank-model row is $46.61 of real spend across 11 runs
> (8 users) where `model` arrived empty — instrumentation gap to fix in
> `_record_user_cost_entry`.

### By user × model (top 25 spenders — full matrix in `data/cost_by_user_model.csv`)

| User | Runs | Total $ | claude-sonnet-4-6 | claude-opus-4-6 | (blank) | gpt-5.4 | gpt-5.2 | claude-opus-4-5-20251101 |
|---|---|---|---|---|---|---|---|---|
| justin-kang@berkeley.edu | 49 | 95.2122 | 8.8999 | 65.561 | 20.7512 |  |  |  |
| toledosean@gmail.com | 23 | 29.6861 | 1.0125 | 26.1589 | 2.5147 |  |  |  |
| anon:ea626e57 | 4 | 26.6956 | 19.5908 |  | 7.1049 |  |  |  |
| stevenyang.dev@gmail.com | 4 | 18.6177 | 14.4675 | 4.1502 |  |  |  |  |
| jacob.a.quion@gmail.com | 12 | 15.2094 | 11.6111 |  | 3.5983 |  |  |  |
| kshitijkumar3@gmail.com | 11 | 14.0953 | 10.8926 | 1.6428 | 1.5599 |  |  |  |
| sahasrakokkula77@gmail.com | 12 | 12.1694 | 12.1694 |  |  |  |  |  |
| philipnisevich@gmail.com | 4 | 11.7631 | 11.7631 |  |  |  |  |  |
| enochfyw@gmail.com | 7 | 10.5325 | 10.5325 |  |  |  |  |  |
| kakanisnehil@gmail.com | 2 | 8.2761 | 8.2761 |  |  |  |  |  |
| noriaki@uni.minerva.edu | 4 | 8.1042 | 8.1042 |  |  |  |  |  |
| owin@owinrojas.com | 3 | 7.5782 | 3.4893 | 4.089 |  |  |  |  |
| umangshankar10@gmail.com | 2 | 7.4295 | 7.4295 |  |  |  |  |  |
| stepodkelly@gmail.com | 1 | 7.3752 |  |  | 7.3752 |  |  |  |
| amyhsieh3730@gmail.com | 2 | 6.9995 | 6.9995 |  |  |  |  |  |
| nagatarunmoturi@gmail.com | 16 | 6.6975 | 6.6975 |  |  |  |  |  |
| clai74@mail.ccsf.edu | 2 | 6.0836 | 6.0836 |  |  |  |  |  |
| benjinisevich2@gmail.com | 6 | 5.2268 | 5.2268 |  |  |  |  |  |
| anon:knemavat | 4 | 4.9567 | 4.9567 |  |  |  |  |  |
| mborgiottitulane@gmail.com | 2 | 4.8148 | 4.8148 |  |  |  |  |  |
| anon:Rosekr1 | 10 | 4.4899 | 4.4899 |  |  |  |  |  |
| kewinszlezingier@gmail.com | 1 | 4.2283 | 4.2283 |  |  |  |  |  |
| misha@mypipdev.com | 3 | 4.1992 | 4.1992 |  |  |  |  |  |
| amberkaurtoor@gmail.com | 2 | 4.1081 | 4.1081 |  |  |  |  |  |
| schan119@calpoly.edu | 2 | 4.0432 | 4.0432 |  |  |  |  |  |

### By project (top 20 — full list in `data/cost_by_project.csv`)

| Project id | Owner | Runs | Total $ | Models |
|---|---|---|---|---|
| 44090311-4bd8-4f29-9348-091c7ecb388f | justin-kang@berkeley.edu | 18 | 86.3122 | (blank), claude-opus-4-6 |
| prj_b180bd849abe4731b391c1dd585be000 |  | 4 | 26.6956 | (blank), claude-sonnet-4-6 |
| prj_9408e7836d3240fcb14fa6ae0caa0453 | toledosean@gmail.com | 19 | 19.975 | (blank), claude-opus-4-6, claude-sonnet-4-6 |
| 3296f689-9bf7-44b2-bb76-171ca01186a3 | stevenyang.dev@gmail.com | 4 | 18.6177 | claude-opus-4-6, claude-sonnet-4-6 |
| prj_07924aa5d8844a4c92ec1db23476ff4a | jacob.a.quion@gmail.com | 12 | 15.2094 | (blank), claude-sonnet-4-6 |
| prj_b88f4c0b585642c899688ce48603ea48 | kshitijkumar3@gmail.com | 11 | 14.0952 | (blank), claude-opus-4-6, claude-sonnet-4-6 |
| prj_4a221e53ef884270ad1424fee9f41f90 | sahasrakokkula77@gmail.com | 12 | 12.1694 | claude-sonnet-4-6 |
| fa325ad8-92a1-460b-bebc-6e41d0744990 | philipnisevich@gmail.com | 4 | 11.7631 | claude-sonnet-4-6 |
| prj_4f409ce952ed458ebf2627aa06c44fad | enochfyw@gmail.com | 7 | 10.5325 | claude-sonnet-4-6 |
| prj_bfde8a2032ee4e6c9ea636a6afcadf2c | justin-kang@berkeley.edu | 31 | 8.8999 | claude-sonnet-4-6 |
| prj_154ea02e80f04b71877b98956e565c12 | kakanisnehil@gmail.com | 2 | 8.2761 | claude-sonnet-4-6 |
| 9f23a6c7-a167-4b13-aa92-58e43f20cb1d | noriaki@uni.minerva.edu | 4 | 8.1042 | claude-sonnet-4-6 |
| prj_d071db4af98d4fe1a789f8c1bb45b0e6 | umangshankar10@gmail.com | 2 | 7.4295 | claude-sonnet-4-6 |
| prj_7782ae176a0f4d33bbee7296d3956151 | stepodkelly@gmail.com | 1 | 7.3752 | (blank) |
| prj_ce4dd6df91864d219f2baa8910a1d9ea | toledosean@gmail.com | 1 | 7.337 | claude-opus-4-6 |
| 730ceb72-ce18-4665-aeb1-94ca18c2a89c | clai74@mail.ccsf.edu | 2 | 6.0836 | claude-sonnet-4-6 |
| prj_826a6397e8994cdf9b1284c5daf5d5ac | amyhsieh3730@gmail.com | 1 | 5.8299 | claude-sonnet-4-6 |
| prj_6d60ee35c5824b948b8c4dddff7c74e6 | owin@owinrojas.com | 2 | 4.8246 | claude-opus-4-6, claude-sonnet-4-6 |
| fa55ae9f-922d-4eff-ae70-bf6acb005dbb | mborgiottitulane@gmail.com | 2 | 4.8148 | claude-sonnet-4-6 |
| prj_51062113208340d5befa46d932c1d25e |  | 10 | 4.4899 | claude-sonnet-4-6 |

### BYOK vs platform keys

- **BYOK:** 1 run / $0.31 — likhith11ramesh@gmail.com
- **Platform (non-BYOK):** 229 runs / $351.45

Per-turn rows (timestamp, user, model, $, byok, project, run_id): `data/cost_per_turn.csv` (230 rows).

---

## 7. Deploys

| Kind | Clicks (users) | Succeeded (users) | Failed (users) |
|---|---|---|---|
| **Sandbox** | 38 (9) | **20 (6)** | 21 (9) |
| **Production** | 9 (5) | **6 (2)** | 1 (1) |

Status values on outcomes: production_failed:failed×1 · production_succeeded:running×6 · sandbox_failed:failed×21 · sandbox_succeeded:running×20
Deploy-upsell clicks (locked deploy → upgrade modal): 9 by 6 users.

### Per deployer — clicked/succeeded/failed

| User | Sandbox c/s/f | Production c/s/f | AI turns | Projects created |
|---|---|---|---|---|
| wanzelin007@gmail.com | 9/8/0 | 5/5/0 | 1 | 0 |
| sahilnale@icloud.com | 4/4/0 | 0/0/0 | 5 | 1 |
| kakanisnehil@gmail.com | 9/3/5 | 1/0/0 | 4 | 1 |
| benjinisevich2@gmail.com | 8/2/2 | 1/1/0 | 7 | 0 |
| rishabh.rb@icloud.com | 2/2/0 | 0/0/0 | 3 | 0 |
| philipnisevich@gmail.com | 2/1/1 | 1/0/1 | 4 | 0 |
| bnisevich@gmail.com | 2/0/0 | 0/0/0 | 0 | 0 |
| kvenugop@usc.edu | 1/0/2 | 0/0/0 | 0 | 0 |
| anon:2ab5b433 | 0/0/0 | 1/0/0 | 0 | 0 |
| harshjannawar14@gmail.com | 1/0/2 | 0/0/0 | 2 | 0 |

### "Deploy-only" users (deploy activity, zero AI turns & zero projects in-window)

| User | Sandbox c/s/f | Production c/s/f |
|---|---|---|
| bnisevich@gmail.com | 2/0/0 | 0/0/0 |
| kvenugop@usc.edu | 1/0/2 | 0/0/0 |
| anon:2ab5b433 | 0/0/0 | 1/0/0 |

---

## 8. GitHub

- **Connected successfully: 13 users** — chengreric@gmail.com, enochfyw@gmail.com, jacob.a.quion@gmail.com, justin-kang@berkeley.edu, kakanisnehil@gmail.com, kshitijkumar3@gmail.com, kvenugop@usc.edu, noliversauce@gmail.com, noriaki@uni.minerva.edu, rishabh.rb@icloud.com, ryanxu240@gmail.com, sahilnale@icloud.com, umangshankar10@gmail.com
- Clicked but no success in-window: —
- Failures: jacob.a.quion@gmail.com (21:35), enochfyw@gmail.com (23:23)
- No `git_commit_*` events fired in the window (nobody used in-IDE git commit).

---

## 9. Upgrades & monetization

- Intent: **49 checkout clicks** by 40 users; 22 top-up clicks by 6 users.
- **Completed: 44 upgrades** by 43 users — **$970.00** total checkout value.
- Failed checkouts: 3 (anon:2ab5b433, enochfyw@gmail.com, jczhang223@gmail.com).

### Plan transitions

| Transition (interval) | Count | $ total |
|---|---|---|
| free → pro (month) | 30 | 750.00 |
| free → builder (month) | 13 | 195.00 |
| builder → pro (month) | 1 | 25.00 |

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

---

## 10. Issues & friction — who hit what

### AI failure reasons

| Reason | Count | Users |
|---|---|---|
| litellm.BadRequestError: AnthropicException - b'{"type":"error","error":{"type": | 14 | likhith11ramesh@gmail.com, mp@gmail.com |
| A turn is already in progress for this project; wait for it to finish. | 13 | anon:ea626e57, justin-kang@berkeley.edu, mborgiottitulane@gmail.com, owin@owinrojas.com, stevenyang.dev@gmail.com |
| This model is no longer in your selected models (Dashboard → AI Models). Pick an | 4 | likhith11ramesh@gmail.com |
| litellm.APIError: APIError: OpenrouterException - {"error":{"message":"This requ | 3 | mp@gmail.com |
| Agent did not respond. Please try again. | 2 | anon:ea626e57, toledosean@gmail.com |
| Exception: Walker ai_chat failed: <html>
<head><title>504 Gateway Time-out</tit | 2 | justin-kang@berkeley.edu |
| Connection lost. Please try again. | 1 | mborgiottitulane@gmail.com |
| Tool.make_finish_tool.<locals>.finish_tool() missing 1 required positional argum | 1 | justin-kang@berkeley.edu |

### Quota blocks
5 users hit `ai_message_blocked_quota`: anon:ea626e57, jacob.a.quion@gmail.com, kakanisnehil@gmail.com, kewinszlezingier@gmail.com, mborgiottitulane@gmail.com

### Preview failures
| Time | User | Reason | Phase |
|---|---|---|---|
| 2026-07-26 22:28:42.200000 | sahilnale@icloud.com | max_retries | sandbox_gone |
| 2026-07-27 00:01:57.651000 | harshjannawar14@gmail.com | max_retries | sandbox_gone |

### Per-user issue log (all users who hit anything)

| User | Issues (event×count) |
|---|---|
| likhith11ramesh@gmail.com | failed×17 |
| anon:ea626e57 | blocked_quota×1 · failed×6 · ai_user_aborted×6 |
| justin-kang@berkeley.edu | failed×6 · ai_user_aborted×5 |
| mborgiottitulane@gmail.com | blocked_quota×5 · failed×3 |
| owin@owinrojas.com | failed×2 · ai_user_aborted×2 |
| mp@gmail.com | failed×4 |
| sahilnale@icloud.com | ai_user_aborted×1 · preview_failed×1 |
| kewinszlezingier@gmail.com | blocked_quota×2 |
| kakanisnehil@gmail.com | blocked_quota×2 |
| sahasrakokkula77@gmail.com | ai_user_aborted×2 |
| stevenyang.dev@gmail.com | failed×1 · ai_user_aborted×1 |
| toledosean@gmail.com | failed×1 · ai_user_aborted×1 |
| aneeshpradhan@acm.org | ai_user_aborted×1 |
| jacob.a.quion@gmail.com | blocked_quota×1 |
| schan119@calpoly.edu | ai_user_aborted×1 |
| yujiwork@outlook.com | ai_user_aborted×1 |
| benjinisevich2@gmail.com | ai_user_aborted×1 |
| chengreric@gmail.com | ai_user_aborted×1 |
| anon:Rosekr1 | ai_user_aborted×1 |
| stepodkelly@gmail.com | ai_user_aborted×1 |
| rishabh.rb@icloud.com | ai_user_aborted×1 |
| harshjannawar14@gmail.com | preview_failed×1 |

> No `$exception` (JS error) events landed in the window, and no `project_creation_failed` fired.

---

## 11. Method & caveats

- **Window:** `timestamp >= '2026-07-26 17:00:00' AND < '2026-07-27 00:30:00'` — PostHog project TZ is UTC (verified).
- **Env filter:** `environment='prod' OR $host IN (jachammer.ai, www.jachammer.ai, jac-builder.jaseci.org)` on every query.
- **Cost** = `ai_generation_metered.cost_usd` (server-emitted litellm metered $; platform's real spend). BYOK runs are the user's own key — their `cost_usd` is what the user's key was billed, not platform spend.
- **Per-turn** = one `ai_generation_metered` row per generation run; `ai_message_completed` corroborates model/turn threading.
- `person.properties.plan/email` are **current** person values (post-window). `anon:` users never identified (guest traffic).
- `project_created` lacks `project_id` → project cost table joins on ids from AI/preview events; projects with zero AI runs don't appear in the cost table.
- 11 metered runs have empty `model` ($46.61) — fix in jac-ide `_record_user_cost_entry`.

### Files
| File | Contents |
|---|---|
| `SUMMARY.md` | Executive summary |
| `REPORT.md` | This report |
| `data/users_activity.csv` | Full per-user rollup (283 rows, every counter) |
| `data/signups.csv` · `data/projects_created.csv` | Row-level signups / projects |
| `data/cost_per_turn.csv` | 230 per-turn cost rows (user, model, $, byok, project, run) |
| `data/cost_by_user_model.csv` · `data/cost_by_project.csv` | Cost matrices |
| `data/upgrades_and_topups.csv` · `data/deploy_events.csv` · `data/github_events.csv` · `data/issue_events.csv` | Row-level detail |
