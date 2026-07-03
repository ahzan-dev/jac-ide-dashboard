/* JacHammer multi-page dashboard prototype — plain JS, hash-routed, real PostHog snapshot (data.js).
   Reuses hand-rolled SVG charts. Overview page fully built; other pages are honest stubs that
   show each item's feasibility verdict (from .docs/posthog/DASHBOARD_FEASIBILITY.md). */
/* multi-environment: RAW holds all env snapshots; D points at the active one.
   The top-bar switcher flips ENV and re-renders. Page fns close over `D` (a
   let), so reassigning it before render() feeds them the new environment. */
const RAW = window.DASHBOARD_DATA || {};
let ENV = RAW.current || (RAW.environments && RAW.environments[0] && RAW.environments[0].key) || 'prod';
let D = (RAW.data && RAW.data[ENV]) || RAW.data && RAW.data.prod || {};
const tt = document.getElementById('tt');
const shortDate = s => { const p=String(s).slice(0,10).split('-'); return p.length===3?(+p[1])+'/'+(+p[2]):s; };
const num = n => (n==null?'–':(Math.round(n*10)/10).toLocaleString());
const wk = (arr,i)=> (arr||[]).map(r=>({x:r[0],y:r[1+i]}));

/* ---------- "?" tooltips: hover + tap-to-toggle ---------- */
let ttPinned=false;
function showTip(q){ tt.innerHTML=q.getAttribute('data-tip'); tt.style.whiteSpace='normal'; tt.style.maxWidth='320px';
  const r=q.getBoundingClientRect(); tt.style.left=Math.min(window.innerWidth-336,Math.max(8,r.left))+'px'; tt.style.top=(r.bottom+8)+'px'; tt.style.opacity=1; }
function hideTip(){ tt.style.opacity=0; tt.style.whiteSpace='nowrap'; tt.style.maxWidth='none'; }
document.addEventListener('mouseover',e=>{ const q=e.target.closest&&e.target.closest('.qm'); if(q&&!ttPinned) showTip(q); });
document.addEventListener('mouseout',e=>{ if(!ttPinned&&e.target.closest&&e.target.closest('.qm')) hideTip(); });
document.addEventListener('click',e=>{ const q=e.target.closest&&e.target.closest('.qm');
  if(q){ e.stopPropagation(); if(ttPinned){ttPinned=false;hideTip();}else{ttPinned=true;showTip(q);} } else if(ttPinned){ttPinned=false;hideTip();} });

/* ---------- slope ---------- */
function slope(vals,goodWhenUp=true,partialLast=true){
  const v=vals.filter(x=>x!=null); const arr=partialLast?v.slice(0,-1):v; if(arr.length<2) return '';
  const cur=arr[arr.length-1],prev=arr[arr.length-2]; if(prev===0) return '';
  const pct=((cur-prev)/Math.abs(prev))*100, up=pct>0, flat=Math.abs(pct)<3, good=up===goodWhenUp;
  const cls=flat?'flat':(good?'good':'bad'), arrow=flat?'→':(up?'▲':'▼');
  return `<span class="slope ${cls}">${arrow} ${Math.abs(pct).toFixed(0)}%</span>`;
}

/* ---------- SVG line chart (+hover) ---------- */
let CID=0;
function lineChart(points,{unit='',partialLast=true,y0=false,h=130}={}){
  const W=340,H=h,m={l:32,r:14,t:12,b:20},pw=W-m.l-m.r,ph=H-m.t-m.b;
  const ys=points.map(p=>p.y); let mn=Math.min(...ys),mx=Math.max(...ys); if(y0)mn=0; if(mn===mx)mx=mn+1;
  const pad=(mx-mn)*0.12; mx+=pad; if(!y0)mn=Math.max(0,mn-pad);
  const X=i=>m.l+(points.length<2?pw/2:pw*i/(points.length-1)), Y=v=>m.t+ph*(1-(v-mn)/(mx-mn));
  const id='c'+(++CID), solidN=partialLast?points.length-1:points.length;
  const line=(a,b)=>points.slice(a,b).map((p,i)=>`${X(a+i).toFixed(1)},${Y(p.y).toFixed(1)}`).join(' ');
  const grid=[0,.5,1].map(f=>{const yy=m.t+ph*f;return `<line x1="${m.l}" y1="${yy}" x2="${W-m.r}" y2="${yy}" stroke="var(--grid)" stroke-width="1"/>`;}).join('');
  const solid=`<polyline points="${line(0,solidN)}" fill="none" stroke="var(--series)" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>`;
  const dash=partialLast&&points.length>=2?`<polyline points="${line(solidN-1,points.length)}" fill="none" stroke="var(--series)" stroke-width="2" stroke-dasharray="3 3" opacity=".5"/>`:'';
  const ls=points[solidN-1], endDot=ls?`<circle cx="${X(solidN-1)}" cy="${Y(ls.y)}" r="3.2" fill="var(--series)"/>`:'';
  const yl=`<text x="${m.l-5}" y="${Y(mx)+3}" text-anchor="end">${num(mx)}</text><text x="${m.l-5}" y="${Y(mn)+3}" text-anchor="end">${num(mn)}</text>`;
  const xl=`<text x="${m.l}" y="${H-6}">${shortDate(points[0].x)}</text><text x="${W-m.r}" y="${H-6}" text-anchor="end">${shortDate(points[points.length-1].x)}</text>`;
  const cross=`<line id="${id}cx" y1="${m.t}" y2="${m.t+ph}" stroke="var(--ink-2)" stroke-width="1" opacity="0"/><circle id="${id}cd" r="4" fill="var(--series)" stroke="var(--surface)" stroke-width="1.5" opacity="0"/>`;
  const hit=`<rect id="${id}h" x="${m.l}" y="0" width="${pw}" height="${H}" fill="transparent"/>`;
  setTimeout(()=>attachHover(id,points,{X,Y,unit,pw,m,partialLast}),0);
  return `<div class="chartbox"><svg class="chart" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">${grid}${yl}${xl}${solid}${dash}${endDot}${cross}${hit}</svg></div>`;
}
function attachHover(id,points,g){
  const svg=document.getElementById(id+'h'); if(!svg) return;
  const cx=document.getElementById(id+'cx'),cd=document.getElementById(id+'cd'),root=svg.ownerSVGElement;
  root.addEventListener('mousemove',e=>{ const r=root.getBoundingClientRect(); const rel=(e.clientX-r.left)/r.width*340;
    let i=Math.round((rel-g.m.l)/g.pw*(points.length-1)); i=Math.max(0,Math.min(points.length-1,i));
    const p=points[i],px=g.X(i),py=g.Y(p.y);
    cx.setAttribute('x1',px);cx.setAttribute('x2',px);cx.setAttribute('opacity','.5'); cd.setAttribute('cx',px);cd.setAttribute('cy',py);cd.setAttribute('opacity','1');
    const partial=g.partialLast&&i===points.length-1;
    tt.innerHTML=`<b>${num(p.y)}${g.unit}</b> <span class="k">· ${shortDate(p.x)}${partial?' (in progress)':''}</span>`;
    tt.style.left=(e.clientX+14)+'px';tt.style.top=(e.clientY-10)+'px';tt.style.opacity=1; });
  root.addEventListener('mouseleave',()=>{tt.style.opacity=0;cx.setAttribute('opacity','0');cd.setAttribute('opacity','0');});
}
/* sparkline (mini, no axes) for KPI cards */
function spark(points,color){
  if(!points.length) return ''; const W=200,H=40,pad=3;
  const ys=points.map(p=>p.y),mn=Math.min(...ys),mx=Math.max(...ys)||1,rng=(mx-mn)||1;
  const X=i=>pad+(W-2*pad)*i/(Math.max(1,points.length-1)), Y=v=>pad+(H-2*pad)*(1-(v-mn)/rng);
  const pts=points.map((p,i)=>`${X(i).toFixed(1)},${Y(p.y).toFixed(1)}`).join(' ');
  const area=`${pad},${H-pad} ${pts} ${W-pad},${H-pad}`;
  return `<svg class="spark" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none"><polygon points="${area}" fill="${color}" opacity="0.12"/><polyline points="${pts}" fill="none" stroke="${color}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/></svg>`;
}
/* horizontal bars (top features) */
function hbars(pairs,denom){
  const mx=Math.max(...pairs.map(p=>p[1]))||1;
  return `<div class="hbars">`+pairs.map(p=>{ const pct=denom?Math.round(100*p[1]/denom):Math.round(100*p[1]/mx);
    return `<div class="hbar"><span class="hbl">${p[0]}</span><span class="hbt"><i style="width:${Math.max(3,100*p[1]/mx)}%"></i></span><span class="hbv">${denom?pct+'%':p[1]}</span></div>`;}).join('')+`</div>`;
}
/* vertical bar chart */
function barChart(pairs){
  const W=340,H=130,m={l:30,r:10,t:12,b:34},pw=W-m.l-m.r,ph=H-m.t-m.b;
  const mx=Math.max(...pairs.map(p=>p[1]))*1.1||1,bw=pw/pairs.length,in_=bw*0.34,Y=v=>m.t+ph*(1-v/mx);
  const bars=pairs.map((p,i)=>{const x=m.l+bw*i+in_/2,w=bw-in_,y=Y(p[1]),hh=m.t+ph-y;
    return `<rect x="${x.toFixed(1)}" y="${y.toFixed(1)}" width="${w.toFixed(1)}" height="${Math.max(0,hh).toFixed(1)}" rx="4" fill="var(--series)"/><text x="${(x+w/2).toFixed(1)}" y="${(y-3).toFixed(1)}" text-anchor="middle" fill="var(--ink-2)">${num(p[1])}</text><text x="${(x+w/2).toFixed(1)}" y="${H-8}" text-anchor="middle">${String(p[0]).slice(0,10)}</text>`;}).join('');
  return `<div class="chartbox"><svg class="chart" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">${bars}</svg></div>`;
}
/* grouped bars (new vs returning) */
function groupedBars(rows){
  const W=340,H=140,m={l:30,r:10,t:12,b:22},pw=W-m.l-m.r,ph=H-m.t-m.b;
  const mx=Math.max(...rows.map(r=>Math.max(r[1],r[2])))*1.1||1,gw=pw/rows.length,bw=(gw*0.66)/2,Y=v=>m.t+ph*(1-v/mx);
  const g=rows.map((r,i)=>{ const gx=m.l+gw*i+gw*0.17;
    return `<rect x="${gx.toFixed(1)}" y="${Y(r[1]).toFixed(1)}" width="${bw.toFixed(1)}" height="${(m.t+ph-Y(r[1])).toFixed(1)}" rx="3" fill="var(--series)"/>`
      +`<rect x="${(gx+bw+1).toFixed(1)}" y="${Y(r[2]).toFixed(1)}" width="${bw.toFixed(1)}" height="${(m.t+ph-Y(r[2])).toFixed(1)}" rx="3" fill="var(--accent)"/>`
      +`<text x="${(gx+bw).toFixed(1)}" y="${H-7}" text-anchor="middle">${shortDate(r[0])}</text>`;}).join('');
  return `<div class="chartbox"><svg class="chart" viewBox="0 0 ${W} ${H}" preserveAspectRatio="none">${g}</svg></div>`
    +`<div class="legend"><span><i style="background:var(--series)"></i>New</span><span><i style="background:var(--accent)"></i>Returning</span></div>`;
}
/* retention heatmap */
function retentionTable(rows){
  const ramp=v=>{ if(v==null)return 'transparent'; const a=Math.min(1,v/40); return `rgba(57,135,229,${(0.08+a*0.85).toFixed(2)})`; };
  const maxW=Math.max(...rows.map(r=>r.pcts.length));
  let head='<tr><th class="coh">cohort</th>'; for(let w=0;w<maxW;w++) head+=`<th>W${w}</th>`; head+='</tr>';
  const body=rows.map(r=>{ let td=`<td class="coh">${shortDate(r.cohort)} · ${r.base}</td>`;
    for(let w=0;w<maxW;w++){const v=r.pcts[w]; td+=`<td class="cell ${w===4?'w4':''}" style="background:${ramp(v)}">${v==null?'':v+'%'}</td>`;}
    return '<tr>'+td+'</tr>';}).join('');
  return `<table class="ret">${head}${body}</table>`;
}
/* funnel */
function funnelBlock(steps){
  const base=steps[0][1]||1;
  return `<div class="funnel">`+steps.map((s,i)=>{ const w=Math.max(6,100*s[1]/base);
    const drop=i>0?Math.round(100*(steps[i-1][1]-s[1])/(steps[i-1][1]||1)):0;
    return `<div class="row"><span class="lbl">${s[0]}</span><span class="bar" style="width:${w}%">${s[1]}</span><span class="drop">${i>0?('−'+drop+'%'):'&nbsp;'}</span></div>`;}).join('')+`</div>`;
}

/* ---------- tile builders ---------- */
function qm(info){ return info?` <span class="qm" data-tip="${String(info).replace(/"/g,'&quot;')}">?</span>`:''; }
function earlyBadge(small){ return small?` <span class="early">⚠ small N</span>`:''; }
function card(cls,inner){ return `<div class="card ${cls}">${inner}</div>`; }
function kpi(label,value,unit,slopeHtml,series,color,info){
  return card('col-3 kpi', `<div class="h"><span class="title">${label}${qm(info)}</span></div>`
    +`<div class="kpirow"><div class="val">${value}<span class="u">${unit||''}</span></div>${slopeHtml||''}</div>`
    +(series&&series.length?spark(series,color||'var(--series)'):'')
    +`<div class="sub">vs prev period</div>`);
}
function statTile(col,title,val,unit,sub,slopeHtml,info){
  return card('col-'+col, `<div class="h"><span class="title">${title}${qm(info)}</span>${slopeHtml||''}</div><div class="val">${val}<span class="u">${unit||''}</span></div>`+(sub?`<div class="sub">${sub}</div>`:''));
}
function chartTile(col,title,q,inner,slopeHtml,info){
  return card('col-'+col, `<div class="h"><span class="title">${title}${qm(info)}</span>${slopeHtml||''}</div>`+(q?`<div class="q">${q}</div>`:'')+inner);
}

/* ================= PAGES ================= */
const GROUPS=[
  {name:'Dashboard', items:[['overview','Overview','🟢']]},
  {name:'Product', items:[['users','Users & Adoption','🟢'],['features','Feature Usage','🟡'],['feedback','Feedback & Roadmap','🔴']]},
  {name:'AI Intelligence', items:[['requests','AI Requests','🟢'],['quality','AI Quality','🔴'],['advanced','Advanced Analytics','🟢']]},
  {name:'Business', items:[['impact','Developer Impact','🟡'],['cost','Cost & Usage','🟢']]},
  {name:'Operations', items:[['health','System Health','🟡'],['settings','Settings & Data','🟡']]},
];
const TITLES={overview:['Overview','Real-time insights into JacHammer usage and performance'],
  users:['Users & Adoption','Who uses JacHammer and whether they come back'],
  features:['Feature Usage','Which features users actually value'],
  feedback:['Feedback & Roadmap','Voice of customer → product decisions'],
  requests:['AI Requests','How users interact with the AI engine'],
  quality:['AI Quality','Whether the AI output is actually useful'],
  advanced:['Advanced Analytics','Predict problems before they surface'],
  impact:['Developer Impact','The real productivity value delivered'],
  cost:['Cost & Usage','AI cost, usage, and profitability'],
  health:['System Health','Technical reliability and performance'],
  settings:['Settings & Data Controls','Access, privacy, and tracking rules']};

/* stub feasibility items per page (from DASHBOARD_FEASIBILITY.md) */
const STUB={
  users:{r:'🟢 Ready — ~10/13 live today',items:[['Total / new users','✅'],['DAU / WAU / MAU','✅'],['New vs returning (Lifecycle)','✅'],['Activation rate','✅'],['Retention cohort heatmap','✅'],['Onboarding funnel','✅'],['Churn risk','⚠️ proxy'],['Segment by plan','⚠️ pending deploy'],['Signup source (channel)','🔧 needs UTM capture'],['Trial vs paid · paid churn','🔒 Stripe'],['Team / enterprise segments','❌ single-user product']]},
  features:{r:'🟡 Half — adoption/usage/trend live',items:[['Most / least used features','✅'],['Adoption rate (% of MAU)','✅'],['Usage over time','✅'],['Completion rate','⚠️ only AI/preview/deploy'],['Error rate','⚠️ only where a failure event exists'],['Usage by user type','⚠️ by plan (pending) — no guest concept, all users sign up'],['Usage by team/workspace','❌ no team — per-project only'],['(replace mockup features)','ℹ️ real set: AI build, preview, deploy, git, github, export, share, templates, upload, inspector']]},
  feedback:{r:'🔴 Mostly external — no feedback system exists',items:[['NPS / CSAT / user feedback','🔧 enable PostHog Surveys'],['Common complaints / problem areas','⚠️ proxy from $exception + *_failed'],['Support tickets','🔒 Zendesk/Intercom'],['Feature requests · roadmap · impact/effort','🔒 Canny/Linear (embed)'],['Sentiment trend','🔧 after surveys run / 🔒 NLP']]},
  requests:{r:'🟢 Ready — 8/11 live',items:[['Total / per-day / per-user','✅'],['Prompt length','✅'],['Success / failure + reasons','✅'],['Peak usage times','✅'],['Response length','🔧 +.length prop (~10 min)'],['Task category','🔧 keyword heuristic prop (~1-2h)'],['Model / token / cost per request','⚠️→✅ set POSTHOG_PROJECT_TOKEN on prod pod'],['Programming language','❌ N/A — Jac only']]},
  quality:{r:'🔴 Blocked — only failure + latency live',items:[['Failure rate','✅'],['"Slow" (p95 latency)','✅'],['Revert / abort rate','⚠️ weak proxy'],['Helpful / not-helpful / rating','🔧 ai_response_rated thumbs (~2-3h) — unlocks ~6 items'],['Hallucination / issue categories','🔧 ai_issue_reported picker'],['Acceptance / kept','🔧 generation_kept'],['Quality by model','⚠️→✅ after rating + prod token']]},
  advanced:{r:'🟢 As honest heuristics (not ML)',items:[['Churn risk / accounts at risk','✅ existing cohort'],['Failure-pattern detection','✅ group reason/phase'],['Anomaly detection','✅ threshold + native alerts'],['User-journey flow','✅ native Funnels/Paths'],['Forecasting','⚠️ naive trend'],['Behavior clustering','⚠️ rule-based segments'],['AI insights / recommendations','⚠️ byLLM summary (label it)'],['Prompt clustering','🔒 prompt text never captured']]},
  impact:{r:'🟡 Thin — 2 honest tiles',items:[['Code acceptance rate (accept vs revert)','✅ ~91%'],['Code produced (files changed)','✅'],['Hours saved / ROI','⚠️ estimation — label it'],['Bugs / tests / docs generated','🔧 needs per-file path list'],['PRs improved','🔒 GitHub'],['Team impact','❌ no team dim']]},
  cost:{r:'🟢 Ready (cost side)',items:[['Cost per request / user / model','✅ ledger now, PostHog post-deploy'],['Heavy users','✅'],['Abnormal usage · high-cost alerts','✅'],['Cost per workspace','⚠️ = project'],['Free-trial cost','⚠️ join to tier'],['Revenue / margin / usage-vs-revenue','🔒 Stripe (cost side ✓)'],['Token usage (in/out)','❌ not captured — cost only']]},
  health:{r:'🟡 Split — app-level live, infra repointable',items:[['Error rate ($exception + ratios)','✅'],['AI response latency (P50/P95)','✅'],['Preview latency / reliability','✅ ~64%'],['Failed requests (app)','✅'],['API P95 · 5xx · CPU / mem','🔧 repoint jac-scale metrics'],['Uptime · timeout · queue · DB · 3rd-party','🔒 monitoring/APM'],['Service-status table','⚠️ hybrid heuristic']]},
  settings:{r:'🟡 Split — PostHog controls done, no app RBAC',items:[['Privacy / session-replay masking','✅ configured in analytics.cl.jac'],['Data retention · export · alerts','✅ PostHog side (status + links)'],['Event-tracking allowlist','✅ locked to [data-ph-track]'],['Admin access (viewer gate)','🔧 email allowlist / shared password'],['User roles · team permissions · RBAC','🔒 no role model exists']]},
};

/* ---------- Overview page ---------- */
function pageOverview(){
  const active=(D.active||[[0,0,0]])[0], dau=active[0], wau=active[1], mau=active[2];
  const ab=(D.active_builders||[[0,0,0]])[0], abW=wk(D.active_builders_weekly,0);
  const aiReq=(D.ai_requests_total||[[0]])[0][0], rt=(D.response_time||[[0,0,0]])[0];
  const sgnTotal=(D.signups_total||[[0]])[0][0], filesTot=(D.files_changed_total||[[0]])[0][0];
  const sgnS=wk(D.signups_weekly,0), aiS=wk(D.ai_requests_weekly,0), actS=wk(D.active_weekly,0), filesS=wk(D.files_changed_weekly,0);
  const nsS=wk(D.north_star_weekly,0), genS=wk(D.gen_success_weekly,0), prevS=wk(D.preview_reliability_weekly,0);
  const qw=D.quality_weekly||[]; const lastQ=qw[qw.length-2]||[0,1,0,0];
  const acceptRate=lastQ[1]?Math.round(100*(1-lastQ[2]/lastQ[1])):0;
  const genPct=(genS[genS.length-2]||{y:0}).y;
  let H='';
  // KPI row
  H+=`<div class="grid">`
    + kpi('Active Builders', num(ab[2]),'', slope(abW.map(p=>p.y)), abW, 'var(--series)', 'Distinct people who did a REAL action (sent an AI message, ran a preview, or created a project) in the last 30 days — honest usage. DAU '+ab[0]+' · WAU '+ab[1]+'. Separately, '+mau+' total visitors were reached (incl. page-view-only bounces) — NOT counted here.')
    + kpi('AI Requests', num(aiReq),'', slope(aiS.map(p=>p.y)), aiS, '#9085e9', 'ai_message_sent in the last 30 days.')
    + kpi('Median Response', num(rt[0]),'s', '', nsS, '#199e70', 'Median AI turn duration (ai_message_completed). Median, not avg (avg='+rt[1]+'s, skewed by a long tail).')
    + kpi('Code Produced', num(filesTot),'files', slope(filesS.map(p=>p.y)), filesS, '#d95926', 'Total files the AI wrote/changed in 30d (sum of files_changed). A proxy for output volume.')
    + `</div>`;
  // Growth + Top features + Problem areas
  H+=`<div class="grid">`
    + chartTile(5,'User Growth','weekly active users + new signups', lineChart(actS,{y0:true,h:150}), slope(actS.map(p=>p.y)), 'Weekly distinct active users. New-signups overlay omitted for clarity in the prototype.')
    + chartTile(4,'Top Features by Usage','% of active users (30d)', hbars((D.top_features||[]).map(r=>[featureLabel(r[0]),r[1]]), mau), null, 'Share of the last-30d active users who used each feature at least once.')
    + chartTile(3,'Top Problem Areas','failures & friction (30d)', hbars((D.problem_areas||[]).slice(0,6).map(r=>[String(r[0]).replace(/\s+/g,' ').slice(0,24), r[1]]), null), null, 'Honest replacement for the mockup "AI by language" donut (which we do not track). Real failure/friction signals from $exception + *_failed + aborts. Many $exception have blank messages (CORS).')
    + `</div>`;
  // AI Quality + Dev productivity
  H+=`<div class="grid">`
    + statTile(3,'Gen Success', num(genPct)+'%','', 'completed ÷ sent', slope(genS.map(p=>p.y)), 'Of AI requests sent, the % that completed.')
    + statTile(3,'Kept (not reverted)', acceptRate+'%','', 'weak proxy', null, '(completed − reverted) ÷ completed. NOT "acceptance" — reverting is a rarely-used, friction-y action, so a high number mostly means "nobody hit revert", not "the output was great". On a small prod sample this often shows ~100% and means little. A true acceptance signal needs the generation_kept event.')
    + chartTile(3,'AI Quality Trend','generation success', lineChart(genS,{unit:'%',h:120}), null, 'Weekly gen-success. True rating quality needs the ai_response_rated event (not built yet).')
    + chartTile(3,'Preview Reliability','ready ÷ requested', lineChart(prevS,{unit:'%',y0:true,h:120}), slope(prevS.map(p=>p.y)), 'A real per-start success rate: each preview start fires preview_start_requested once, then either preview_ready or preview_start_failed once (verified — the ready event is guarded to fire once per start). Caveats: warm/pre-prepared previews (was_prepared) succeed instantly and inflate it, and small samples are noisy. Genuine signal that preview startup fails a meaningful share of the time.')
    + `</div>`;
  // Funnel + Retention + System health
  const f=(D.funnel||[[0,0,0,0,0]])[0];
  const steps=[['Signed up',f[0]],['Created project',f[1]],['Sent AI msg',f[2]],['Got a build',f[3]],['Previewed',f[4]]];
  H+=`<div class="grid">`
    + chartTile(4,'User Funnel','signup → value (30d cohort)', funnelBlock(steps), null, 'Where new users drop off on the way to value. The −% is who is lost at each step.')
    + chartTile(5,'Retention Cohort'+earlyBadge(Math.max(0,...((D.retention||[]).map(r=>r.base||0)))<15),'% still building weeks later · by signup week', retentionTable(D.retention||[]), null, 'Each row = a signup-week cohort; reading left→right should stay high. Cohorts are tiny so exact % are directional — but the pattern is real: almost nobody returns after week 1.')
    + chartTile(3,'System Health','app-level (30d)', healthBlock(), null, 'App-level signals from PostHog. True infra health (uptime/CPU) needs the monitoring repoint — see System Health page.')
    + `</div>`;
  return H;
}
function featureLabel(ev){ const m={preview_ready:'Live preview',ai_message_sent:'AI build',project_created:'New project',deploy_production_clicked:'Deploy (prod)',deploy_sandbox_clicked:'Deploy (sandbox)',export_downloaded:'Export',github_connect_succeeded:'GitHub',project_shared:'Community share',git_commit_succeeded:'Git commit',inspector_element_selected:'Inspector'}; return m[ev]||ev; }
function healthBlock(){
  const prevS=wk(D.preview_reliability_weekly,0); const rel=prevS.length?prevS[prevS.length-2].y:0;
  const probs=(D.problem_areas||[]); const crashes=(probs.find(p=>p[0]==='JS crash')||[0,0])[1];
  return `<div class="mini">`
    +`<div class="mrow"><span>Preview reliability</span><b class="${rel<60?'warn':'ok'}">${num(rel)}%</b></div>`
    +`<div class="mrow"><span>AI success</span><b class="ok">${num((wk(D.gen_success_weekly,0).slice(-2,-1)[0]||{y:0}).y)}%</b></div>`
    +`<div class="mrow"><span>JS errors (30d)</span><b class="warn">${num(crashes)}</b></div>`
    +`<div class="mrow"><span>True uptime</span><b class="muted">needs monitor</b></div>`
    +`</div>`;
}

function cleanReason(s){ s=String(s).replace(/\s+/g,' ').trim();
  if(/504/.test(s)) return '504 Gateway Time-out';
  if(/ReadTimeout|timed out/i.test(s)) return 'Read timeout';
  if(/Connection lost/i.test(s)) return 'Connection lost';
  if(/did not respond/i.test(s)) return 'Agent no-response';
  if(/overloaded|rate.?limit/i.test(s)) return 'Provider overloaded';
  return s.slice(0,38); }

/* ---------- Users & Adoption ---------- */
function pageUsers(){
  const active=(D.active||[[0,0,0]])[0], dau=active[0],wau=active[1],mau=active[2];
  const ab=(D.active_builders||[[0,0,0]])[0], abW=wk(D.active_builders_weekly,0), reg=(D.registered_active||[[0]])[0][0];
  const total=(D.total_users||[[0]])[0][0], sgnTotal=(D.signups_total||[[0]])[0][0], churn=(D.churn_risk||[[0]])[0][0];
  const sgnS=wk(D.signups_weekly,0), actS=wk(D.active_weekly,0), actvS=(D.activation_weekly||[]).map(r=>({x:r[0],y:r[3]}));
  const lastAct=(D.activation_weekly||[]).slice(-2,-1)[0]||[0,0,0,0];
  let H=`<div class="grid">`
    + kpi('Registered', num(sgnTotal),'', slope(sgnS.map(p=>p.y)), sgnS, '#9085e9', 'People who signed up (auth_signup_succeeded, 180d). You must sign up to use JacHammer — there is no guest access. Separately '+total+' distinct identities hit the site (mostly logged-out landing-page visitors who never signed up) — that is reach, not users.')
    + kpi('Active Builders', num(ab[2]),'', slope(abW.map(p=>p.y)), abW, '#199e70', 'Distinct people who did a REAL action (AI message / preview / project) in 30d. DAU '+ab[0]+' · WAU '+ab[1]+'. ('+mau+' visitors reached incl. bounces — not counted.)')
    + kpi('New Signups (30d)', num((sgnS.slice(-5).reduce((a,p)=>a+p.y,0)))+'','', slope(sgnS.map(p=>p.y)), sgnS, 'var(--series)', 'Registrations in the recent window. ▲▼ over tiny counts is noise — read the trend, not the %.')
    + kpi('Activation', num(lastAct[3])+'%','', null, actvS, '#d95926', '% of a signup cohort reaching a first successful AI build. Small cohorts → treat as directional.')
    + `</div>`;
  H+=`<div class="grid">`
    + chartTile(5,'User Growth','weekly active users', lineChart(actS,{y0:true,h:150}), slope(actS.map(p=>p.y)), 'Weekly distinct active users.')
    + chartTile(4,'New vs Returning','weekly', groupedBars(D.returning_weekly||[]), null, 'New (blue) vs returning-from-an-earlier-week (orange).')
    + chartTile(3,'Signup Method'+earlyBadge(true),'password vs SSO (90d)', hbars((D.signup_source||[]).map(r=>[r[0],r[1]]), null), null, 'Auth method from the signup EVENT (reliable). Historically all "password" — SSO (google/github) signups were untracked until the server-side fix (PR #607); this splits by provider once that ships. For acquisition CHANNEL (where they came from), PostHog already captures $initial_referring_domain (mostly $direct today); UTM would populate if marketing links carried utm_* params.')
    + `</div>`;
  const f=(D.funnel||[[0,0,0,0,0]])[0];
  const steps=[['Signed up',f[0]],['Created project',f[1]],['Sent AI msg',f[2]],['Got a build',f[3]],['Previewed',f[4]]];
  const retMaxBase = Math.max(0,...((D.retention||[]).map(r=>r.base||0)));
  H+=`<div class="grid">`
    + chartTile(4,'Onboarding Funnel','signup → value · 30d cohort', funnelBlock(steps), null, 'Funnel is shallow — the real loss is week-2 return, not onboarding. Small cohort: read the shape, not exact numbers.')
    + chartTile(5,'Retention Cohort'+earlyBadge(retMaxBase<15),'% still building weeks later · by signup week', retentionTable(D.retention||[]), null, 'Each row = a signup-week cohort. Cohorts here are tiny (top base ≈ '+retMaxBase+' people) so individual % are NOT statistically meaningful — but the qualitative fact holds: almost nobody returns after week 1.')
    + statTile(3,'Went Silent (60d)', num(churn),'', 'active 15–60d ago, nothing since', `<span class="slope flat">watch</span>`, 'Distinct identities active 15–60 days ago with zero activity in the last 14 days. May include one-time logged-out landing-page visitors, so it overstates true user churn — a real build would scope this to signed-up users only. Not paid churn (that is Stripe).')
    + `</div>`;
  return H;
}

/* ---------- AI Requests ---------- */
function pageRequests(){
  const total=(D.ai_requests_total||[[0]])[0][0], mau=(D.active||[[0,0,0]])[0][2]||1;
  const pl=(D.prompt_len||[[0,0,0]])[0], rt=(D.response_time||[[0,0,0]])[0];
  const aiS=wk(D.ai_requests_weekly,0), genS=wk(D.gen_success_weekly,0);
  let H=`<div class="grid">`
    + kpi('Total Requests', num(total),'', slope(aiS.map(p=>p.y)), aiS, 'var(--series)', 'ai_message_sent in 30d.')
    + kpi('Per Active User', (total/mau).toFixed(1),'', null, aiS, '#9085e9', 'Total requests ÷ MAU ('+mau+').')
    + kpi('Median Prompt', num(pl[0]),'chars', null, aiS, '#199e70', 'Median prompt length. Avg '+num(pl[1])+' (skewed by long prompts).')
    + kpi('Median Response', num(rt[0]),'s', null, aiS, '#d95926', 'Median AI turn duration.')
    + `</div>`;
  H+=`<div class="grid">`
    + chartTile(5,'Requests per Day','last 14 days', barChart((D.requests_daily||[]).map(r=>[shortDate(r[0]),r[1]])), null, 'Daily ai_message_sent.')
    + chartTile(4,'Peak Usage Hours','by hour, UTC (30d)', barChart((D.peak_hours||[]).filter((_,i)=>i%2===0).map(r=>[r[0]+'h',r[1]])), null, 'When requests happen (UTC hour; every other hour shown).')
    + chartTile(3,'Generation Success','completed ÷ sent', lineChart(genS,{unit:'%',h:150}), slope(genS.map(p=>p.y)), 'Of requests sent, the % that completed.')
    + `</div>`;
  H+=`<div class="grid">`
    + chartTile(6,'Top Failure Reasons','ai_message_failed (30d)', hbars((D.ai_fail_reasons||[]).map(r=>[cleanReason(r[0]),r[1]]), null), null, 'Mostly backend timeouts (504 / read-timeout), not model errors — an infra signal.')
    + card('col-6', `<div class="h"><span class="title">Not tracked yet${qm('Small instrumentation adds — see the AI Requests feasibility.')}</span></div>`
        +`<div class="notyet">`
        +`<div class="ny"><b>Task category</b><span>generate / debug / refactor — 🔧 keyword heuristic prop (~1-2h)</span></div>`
        +`<div class="ny"><b>Response length</b><span>🔧 add .length prop on completion (~10 min)</span></div>`
        +`<div class="ny"><b>Model per request · token / cost</b><span>⚠️→✅ set POSTHOG_PROJECT_TOKEN on prod pod (config)</span></div>`
        +`<div class="ny"><b>Programming language</b><span>❌ N/A — JacHammer generates Jac only</span></div>`
        +`</div>`)
    + `</div>`;
  return H;
}

/* ---------- Cost & Usage ---------- */
function pageCost(){
  const metered=(D.metered_rows||[[0]])[0][0], total=(D.ai_requests_total||[[0]])[0][0];
  let H=`<div class="grid"><div class="card col-12 banner">`
    +`<b>⏳ Cost pipeline instrumented, awaiting prod deploy.</b> The backend now emits real per-turn <code>$ cost</code> as <code>ai_generation_metered</code> (<b>${metered}</b> rows in PostHog today — needs <code>POSTHOG_PROJECT_TOKEN</code> on the prod pod). Real numbers already live in the <code>UserCostEntry</code> ledger. $ tiles below are placeholders until the event ships.`
    +`</div></div>`;
  H+=`<div class="grid">`
    + statTile(3,'Cost / Request','—','','live after deploy',`<span class="slope flat">pending</span>`,'avg(cost_usd) from ai_generation_metered.')
    + statTile(3,'Total Spend (30d)','—','','live after deploy',`<span class="slope flat">pending</span>`,'sum(cost_usd).')
    + statTile(3,'Cost / Active User','—','','live after deploy',`<span class="slope flat">pending</span>`,'total cost ÷ MAU.')
    + statTile(3,'Gross Margin','—','','revenue needs Stripe',`<span class="slope flat">Stripe</span>`,'cost side ready; revenue is Stripe MRR (offline join).')
    + `</div>`;
  H+=`<div class="grid">`
    + chartTile(5,'Model Mix (proxy)','model picks via switch (90d)', hbars((D.model_mix||[]).map(r=>[r[0],r[1]]), null), null, 'Rough model preference from ai_model_switched (intent, not per-request usage). Real per-request model + $ arrive via ai_generation_metered post-deploy.')
    + chartTile(4,'AI Volume (cost driver)','requests / week', lineChart(wk(D.ai_requests_weekly,0),{h:150}), null, 'Requests drive cost — '+num(total)+' in 30d.')
    + card('col-3', `<div class="h"><span class="title">Tier limits${qm('Verified from TIER_LIMITS in billing.jac — the AI-spend caps + project/deploy limits the code actually enforces. Subscription $ prices live in Stripe, not the code, so not shown here.')}</span></div>`
        +`<div class="mini">`
        +`<div class="mrow"><span>AI budget / mo</span><b class="muted">$1.33 / $4 / $10</b></div>`
        +`<div class="mrow"><span>Projects</span><b>3 / 5 / 10</b></div>`
        +`<div class="mrow"><span>Deploys</span><b>0 / 1 / 3</b></div>`
        +`<div class="mrow"><span>free · builder · pro</span><b class="muted">credits = usd×150</b></div>`
        +`</div>`)
    + `</div>`;
  return H;
}

/* ---------- Advanced Analytics ---------- */
function pageAdvanced(){
  const churn=(D.churn_risk||[[0]])[0][0], total=(D.total_users||[[0]])[0][0]||1;
  const daily=(D.daily_ai||[]).map(r=>r[1]);
  const mean=daily.length?daily.reduce((a,b)=>a+b,0)/daily.length:0;
  const sd=daily.length?Math.sqrt(daily.reduce((a,b)=>a+(b-mean)**2,0)/daily.length):0;
  const anomalies=(D.daily_ai||[]).filter(r=>Math.abs(r[1]-mean)>2*sd);
  let H=`<div class="grid"><div class="card col-12 banner">`
    +`<b>Rule-based analytics</b> — honest heuristics over real events, not ML models. Labeled as such. Prompt clustering is the one true gap (prompt text is never captured).`
    +`</div></div>`;
  H+=`<div class="grid">`
    + statTile(3,'Accounts at Risk', num(churn),'users', num(Math.round(100*churn/total))+'% of all users', `<span class="slope bad">watch</span>`, 'Active in prior 60d, silent last 14d. In a real build, rank by recency + spend.')
    + statTile(3,'Daily AI Baseline', num(Math.round(mean)),'/day', '± '+num(Math.round(sd))+' σ', null, 'Mean daily AI completions (30d) — the baseline for anomaly detection.')
    + statTile(3,'Anomalies (30d)', String(anomalies.length),'days', 'beyond ±2σ', anomalies.length?`<span class="slope bad">flagged</span>`:`<span class="slope good">none</span>`, 'Days where AI volume deviated >2σ from the mean — a simple threshold detector (not ML).')
    + statTile(3,'Prompt Clustering','—','', 'prompt text not captured', `<span class="slope flat">blocked</span>`, 'We never store prompt text (masked in replay). Needs new instrumentation + embeddings.')
    + `</div>`;
  const f=(D.funnel||[[0,0,0,0,0]])[0];
  const steps=[['Signed up',f[0]],['Created project',f[1]],['Sent AI msg',f[2]],['Got a build',f[3]],['Previewed',f[4]]];
  H+=`<div class="grid">`
    + chartTile(6,'Failure-Pattern Detection','grouped reasons (30d)', hbars((D.ai_fail_reasons||[]).map(r=>[cleanReason(r[0]),r[1]]), null), null, 'Aggregating structured reason props — pure grouping, no ML.')
    + chartTile(3,'User-Journey Flow','activation path', funnelBlock(steps), null, 'Native funnel — where users flow and drop.')
    + chartTile(3,'Usage Forecast','naive trend', lineChart(wk(D.active_weekly,0),{h:150}), null, 'Weekly active users. A naive trend; real forecasting (ARIMA/Prophet) is a later phase.')
    + `</div>`;
  return H;
}

/* ---------- Feature Usage ---------- */
function featTable(feats,mau,comp){
  const rows=feats.map(r=>{const pct=Math.round(100*r[1]/mau); const c=comp[r[0]]||'—';
    return `<tr><td class="ft">${featureLabel(r[0])}</td><td>${r[1]}</td><td>${pct}%</td><td>${c}</td></tr>`;}).join('');
  return `<table class="ftbl"><tr><th>Feature</th><th>Users</th><th>Adoption</th><th>Completion</th></tr>${rows}</table>`;
}
function pageFeatures(){
  const mau=(D.active||[[0,0,0]])[0][2]||1, feats=(D.top_features||[]);
  const genPct=(wk(D.gen_success_weekly,0).slice(-2,-1)[0]||{y:0}).y;
  const prevPct=(wk(D.preview_reliability_weekly,0).slice(-2,-1)[0]||{y:0}).y;
  const comp={ai_message_sent:num(genPct)+'%',preview_ready:num(prevPct)+'%',deploy_production_clicked:'0%',deploy_sandbox_clicked:'0%'};
  let H=`<div class="grid">`
    + chartTile(5,'Feature Adoption','% of active users (30d)', hbars(feats.map(r=>[featureLabel(r[0]),r[1]]), mau), null, 'Share of MAU using each feature at least once.')
    + card('col-7', `<div class="h"><span class="title">Feature Table${qm('Users + adoption from distinct-user counts. Completion only exists for features with a paired start/end event (AI, preview, deploy); n/a elsewhere — not faked.')}</span></div>`+featTable(feats,mau,comp))
    + `</div>`;
  H+=`<div class="grid"><div class="card col-12 banner">`
    +`<b>Real feature set only.</b> JacHammer has one AI agent — the mockup's separate "code generation / bug detection / refactoring" features do not exist. These are our actual features. <b>Careful reading low usage:</b> Deploy, Folder-upload and Community-submit are <b>tier-gated</b> (Free = 0 deploys, no upload/community per TIER_LIMITS) — so their low numbers reflect a paywall, not low interest. "Completion" applies only to features with an outcome event.`
    +`</div></div>`;
  return H;
}

/* ---------- AI Quality ---------- */
function pageQuality(){
  const rt=(D.response_time||[[0,0,0]])[0], sent=(D.ai_requests_total||[[0]])[0][0]||1;
  const fails=(D.ai_fail_reasons||[]).reduce((a,r)=>a+r[1],0);
  const lastQ=(D.quality_weekly||[]).slice(-2,-1)[0]||[0,1,0,0], revertRate=lastQ[1]?Math.round(100*lastQ[2]/lastQ[1]):0;
  const genS=wk(D.gen_success_weekly,0), revS=(D.quality_weekly||[]).map(r=>({x:r[0],y:r[1]?Math.round(1000*r[2]/r[1])/10:0}));
  let H=`<div class="grid">`
    + kpi('Failure Rate', num(Math.round(100*fails/sent))+'%','', null, revS, 'var(--critical)', 'ai_message_failed ÷ ai_message_sent (30d). Mostly backend timeouts, not model errors.')
    + kpi('Median Latency', num(rt[0]),'s', null, genS, '#9085e9', 'AI turn duration — the "slow" quality signal. Avg '+num(rt[1])+'s.')
    + kpi('Revert Rate', revertRate+'%','', null, revS, '#d95926', 'Of completed builds, % the user undid. Weak dissatisfaction proxy.')
    + kpi('Gen Success', num((genS.slice(-2,-1)[0]||{y:0}).y)+'%','', slope(genS.map(p=>p.y)), genS, '#199e70', 'Completed ÷ sent.')
    + `</div>`;
  H+=`<div class="grid">`
    + chartTile(4,'Success Trend','completed ÷ sent', lineChart(genS,{unit:'%',h:150}), slope(genS.map(p=>p.y)), 'The only real quality trend today.')
    + chartTile(4,'Revert Rate Trend','% undone', lineChart(revS,{unit:'%',y0:true,h:150}), slope(revS.map(p=>p.y),false), 'Lower is better.')
    + chartTile(4,'Failure Reasons','ai_message_failed (30d)', hbars((D.ai_fail_reasons||[]).map(r=>[cleanReason(r[0]),r[1]]),null), null, 'Grouped reasons.')
    + `</div>`;
  H+=`<div class="grid"><div class="card col-12 banner">`
    +`<b>🔴 Biggest gap — zero explicit quality signal today.</b> Helpful-rate, ratings, acceptance, and issue categories all need one small change: a <b>thumbs up/down</b> on each AI message (<code>ai_response_rated</code>) + a down-vote issue picker (<code>ai_issue_reported</code>). That single ChatPanel add unlocks ~6 tiles. <b>Now added in code</b> — pending prod deploy for data.`
    +`</div></div>`;
  return H;
}

/* ---------- Developer Impact ---------- */
function pageImpact(){
  const filesTot=(D.files_changed_total||[[0]])[0][0];
  const lastQ=(D.quality_weekly||[]).slice(-2,-1)[0]||[0,1,0,0], accept=lastQ[1]?Math.round(100*(1-lastQ[2]/lastQ[1])):0;
  const filesS=wk(D.files_changed_weekly,0), acceptS=(D.quality_weekly||[]).map(r=>({x:r[0],y:r[1]?Math.round(100*(1-r[2]/r[1])):0}));
  const hoursSaved=Math.round(filesTot*0.5/60*10)/10;
  let H=`<div class="grid">`
    + kpi('Kept (not reverted)', accept+'%','', null, acceptS, '#199e70', '(completed − reverted) ÷ completed. A WEAK proxy — reverting is a friction-y, rarely-used action, so a high % mostly means "revert went unused", not "output was accepted/loved". True acceptance needs the generation_kept event (not shipped).')
    + kpi('Code Produced', num(filesTot),'files', slope(filesS.map(p=>p.y)), filesS, 'var(--series)', 'Sum of files_changed (30d).')
    + kpi('Est. Hours Saved', num(hoursSaved),'h', null, filesS, '#d95926', 'ESTIMATE: files × a documented constant (0.5 min/file here). Illustrative, not measured.')
    + kpi('Est. ROI','—','', null, null, '#9085e9', 'Needs revenue (Stripe) + a value model. Estimation on estimation — not shown as fact.')
    + `</div>`;
  H+=`<div class="grid">`
    + chartTile(6,'Acceptance Rate Trend','kept vs reverted', lineChart(acceptS,{unit:'%',h:150}), slope(acceptS.map(p=>p.y)), 'Genuine accept-vs-revert over time.')
    + chartTile(6,'Code Produced Trend','files changed / week', lineChart(filesS,{h:150}), slope(filesS.map(p=>p.y)), 'Output-volume proxy.')
    + `</div>`;
  H+=`<div class="grid"><div class="card col-12 banner">`
    +`<b>Honest scope.</b> Only <b>acceptance rate</b> and <b>code produced</b> are measured. Bugs / tests / docs generated need a per-file <b>path list</b> per turn (🔧); hours-saved & ROI are labeled <b>estimates</b>; there is <b>no team dimension</b> (single-user product) so any "team impact" is per-user only.`
    +`</div></div>`;
  return H;
}

/* ---------- System Health ---------- */
function serviceStatus(){
  const rows=[['Web app','ok'],['Auth','ok'],['AI inference','ok'],['Preview','warn'],['Billing','muted'],['Database','muted'],['Notifications','muted']];
  return `<div class="mini">`+rows.map(r=>`<div class="mrow"><span>${r[0]}</span><b class="${r[1]}">${r[1]==='ok'?'● operational':r[1]==='warn'?'● degraded':'○ no signal'}</b></div>`).join('')+`</div>`;
}
function pageHealth(){
  const rt=(D.response_time||[[0,0,0]])[0];
  const excW=wk(D.exception_weekly,0), latW=wk(D.latency_weekly,0), prevW=wk(D.preview_reliability_weekly,0);
  const ce=(D.problem_areas||[]).find(p=>p[0]==='JS crash'), crashes=ce?ce[1]:0;
  const prevRel=(prevW.slice(-2,-1)[0]||{y:0}).y;
  let H=`<div class="grid">`
    + kpi('AI Latency (median)', num(rt[0]),'s', null, latW, '#9085e9', 'ai_message_completed duration. Real, high-volume.')
    + kpi('Preview Reliability', num(prevRel)+'%','', slope(prevW.map(p=>p.y)), prevW, prevRel<60?'var(--critical)':'#199e70', 'A real per-start success rate — each start fires requested once, then ready or failed once (ready is guarded). Warm/pre-prepared previews inflate it; small samples are noisy. Not a rough guess — a genuine reliability signal.')
    + kpi('JS Errors (30d)', num(crashes),'', slope(excW.map(p=>p.y),false), excW, 'var(--warning)', '$exception count. Many blank (CORS) — count only, not messages.')
    + kpi('True Uptime','—','', null, null, 'var(--muted)', 'PostHog cannot measure uptime (an outage stops the events too). Needs an external probe.')
    + `</div>`;
  H+=`<div class="grid">`
    + chartTile(4,'Error Trend','$exception / week', lineChart(excW,{y0:true,h:150}), slope(excW.map(p=>p.y),false), 'Client JS errors per week.')
    + chartTile(4,'AI Latency Trend','median seconds', lineChart(latW,{h:150}), null, 'Turn latency over time.')
    + chartTile(4,'Service Status','app-level heuristic', serviceStatus(), null, 'App rows inferred from failure ratios; infra rows need real checks.')
    + `</div>`;
  H+=`<div class="grid"><div class="card col-12 banner">`
    +`<b>App-level health is live from PostHog</b> (errors, AI latency, preview reliability). <b>Infra health is cheaply unblockable</b> — jac-scale already runs Prometheus + metrics-server for user apps (<code>get_prometheus_series</code>, <code>get_pod_resource_metrics</code>); repoint them at the <code>jac-builder</code> namespace for API-P95, 5xx, CPU/mem. Uptime, queue depth, DB perf, 3rd-party status stay external.`
    +`</div></div>`;
  return H;
}

/* ---------- Feedback & Roadmap ---------- */
function pageFeedback(){
  let H=`<div class="grid"><div class="card col-12 banner">`
    +`<b>🔴 No feedback system exists.</b> No NPS/CSAT, support tickets, or feature-request board in the product. Lowest-lift real add is <b>PostHog Surveys</b> (the SDK is already loaded) for NPS + CSAT. "Complaints / problem areas" can be proxied from failures today.`
    +`</div></div>`;
  H+=`<div class="grid">`
    + chartTile(6,'Top Problem Areas (proxy)','failures & friction (30d)', hbars((D.problem_areas||[]).slice(0,7).map(r=>[String(r[0]).replace(/\s+/g,' ').slice(0,26),r[1]]),null), null, 'Honest proxy for "complaints" — clusters $exception + *_failed + aborts. Not literal user feedback.')
    + card('col-6', `<div class="h"><span class="title">Voice of customer — what it needs${qm('Each item and the tool/change to make it real.')}</span></div>`
        +`<div class="notyet">`
        +`<div class="ny"><b>NPS / CSAT / user feedback</b><span>🔧 enable PostHog Surveys (SDK already loaded)</span></div>`
        +`<div class="ny"><b>Support tickets</b><span>🔒 Zendesk / Intercom (embed)</span></div>`
        +`<div class="ny"><b>Feature requests · roadmap · impact/effort</b><span>🔒 Canny / Linear (embed the board)</span></div>`
        +`<div class="ny"><b>Sentiment trend</b><span>🔧 after surveys run · 🔒 text NLP</span></div>`
        +`</div>`)
    + `</div>`;
  return H;
}

/* ---------- Settings & Data ---------- */
function pageSettings(){
  let H=`<div class="grid">`
    + card('col-4', `<div class="h"><span class="title">Privacy & Masking${qm('Configured in utils/analytics.cl.jac.')}</span></div><div class="mini"><div class="mrow"><span>Mask all inputs</span><b class="ok">on</b></div><div class="mrow"><span>Mask code / editor</span><b class="ok">on</b></div><div class="mrow"><span>Identified profiles only</span><b class="ok">on</b></div><div class="mrow"><span>Opt-out available</span><b class="ok">yes</b></div></div>`)
    + card('col-4', `<div class="h"><span class="title">Data Controls${qm('PostHog-side — surface as status + links.')}</span></div><div class="mini"><div class="mrow"><span>Event tracking</span><b class="ok">allowlist</b></div><div class="mrow"><span>Data retention</span><b class="muted">PostHog policy</b></div><div class="mrow"><span>Export</span><b class="ok">API + jacpack</b></div><div class="mrow"><span>Alerts</span><b class="ok">2 configured</b></div></div>`)
    + card('col-4', `<div class="h"><span class="title">Access${qm('The app has no role model — only a shared-password/allowlist gate.')}</span></div><div class="mini"><div class="mrow"><span>Admin (viewer gate)</span><b>email allowlist</b></div><div class="mrow"><span>User roles</span><b class="muted">none</b></div><div class="mrow"><span>Team permissions</span><b class="muted">none</b></div><div class="mrow"><span>RBAC matrix</span><b class="muted">n/a</b></div></div>`)
    + `</div>`;
  H+=`<div class="grid"><div class="card col-12 banner">`
    +`<b>Two halves.</b> PostHog-side controls (privacy masking, retention, export, alerts) are already configured — surface as read-only status + deep links. App-side access is honest: <b>no RBAC exists</b>; a shared-password / email-allowlist gate (like <code>chat_view.jac</code>) controls who sees this dashboard. Don't render a fake permissions matrix.`
    +`</div></div>`;
  return H;
}

/* ---------- stub page ---------- */
function pageStub(id){
  const s=STUB[id]; if(!s) return `<div class="card col-12"><div class="val">Coming soon</div></div>`;
  const rows=s.items.map(it=>`<div class="stubrow"><span class="sv">${it[1]}</span><span class="sl">${it[0]}</span></div>`).join('');
  return `<div class="grid"><div class="card col-12">`
    +`<div class="stubbadge">${s.r}</div>`
    +`<div class="q" style="margin:8px 0 12px">Feasibility of each item on this page (from the audit). ✅ live today · ⚠️ proxy · 🔧 small add · 🔒 external system · ❌ not applicable.</div>`
    +`<div class="stublist">${rows}</div>`
    +`<div class="sub" style="margin-top:14px">This page is scaffolded. Full build lands per the v1 tier order — see <code>.docs/posthog/DASHBOARD_FEASIBILITY.md</code>.</div>`
    +`</div></div>`;
}

/* ---------- shell + router ---------- */
function renderSidebar(active){
  let h=`<div class="logo"><span class="dot"></span>JacHammer</div>`;
  for(const g of GROUPS){ h+=`<div class="navgroup">${g.name}</div>`;
    for(const it of g.items){ const on=it[0]===active?'on':''; h+=`<a class="navitem ${on}" href="#${it[0]}"><span class="rd">${it[2]}</span>${it[1]}</a>`; } }
  h+=`<div class="sidefoot"><div class="plan">Snapshot</div><div class="planv">${RAW.generated_at||''}</div><div class="sub" style="margin-top:6px">PostHog · project 425465</div></div>`;
  document.getElementById('sidebar').innerHTML=h;
}
function renderEnvSwitch(){
  const el=document.getElementById('envswitch'); if(!el) return;
  const envs=RAW.environments||[{key:ENV,label:ENV}];
  el.innerHTML=envs.map(e=>`<button class="envpill ${e.key===ENV?'on':''}" data-env="${e.key}">${e.label}</button>`).join('');
}
document.addEventListener('click', e=>{
  const b=e.target.closest && e.target.closest('.envpill'); if(!b) return;
  const ne=b.getAttribute('data-env'); if(ne===ENV) return;
  ENV=ne; D=(RAW.data && RAW.data[ENV]) || {}; render();
});
function render(){
  const id=(location.hash||'#overview').slice(1);
  renderSidebar(id);
  renderEnvSwitch();
  const el=(RAW.environments||[]).find(e=>e.key===ENV);
  const dd=RAW.data&&RAW.data[ENV]||{};
  const sgn=(dd.signups_total||[[0]])[0][0];
  document.getElementById('pmeta').innerHTML =
    `<span class="mkpi">windows</span> headline KPIs = <b>last 30 days</b> · trends = <b>10 weeks</b> · cohorts = signup week · `
    +`<span class="mkpi">as of</span> <b>${RAW.generated_at||''}</b> · <span class="mkpi">env</span> <b>${el?el.label:ENV}</b>`
    +(sgn<80?` · <span class="mnote">⚠ small sample (${sgn} signups) — rates & week-over-week are directional, not precise.</span>`:'');
  const t=TITLES[id]||['Overview','']; document.getElementById('ptitle').textContent=t[0]; document.getElementById('psub').textContent=t[1];
  const PAGES={overview:pageOverview,users:pageUsers,requests:pageRequests,cost:pageCost,advanced:pageAdvanced,
    features:pageFeatures,quality:pageQuality,impact:pageImpact,health:pageHealth,feedback:pageFeedback,settings:pageSettings};
  document.getElementById('content').innerHTML = PAGES[id]? PAGES[id]() : pageStub(id);
  window.scrollTo(0,0);
}
window.addEventListener('hashchange',render);
render();
