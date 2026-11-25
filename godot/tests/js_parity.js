// Эталон для сверки GDScript-ядра с web/index.html v1.4.0.
// Берёт ПОДЛИННЫЙ код правил и боя из ../../web/index.html (блоки ДАННЫЕ/ПРАВИЛА/соперник, бой simulate…endStep,
// mulberry32, applyQueued), подменяет только графику/звук заглушками и гоняет в node:vm:
//   1) бои из tests/parity_cases.json с фиксированными зёрнами (как сетевой бой: S.rng = mulberry32(seed),
//      заклинания из очереди — через netSync/applyQueued, ИИ-заклинания — aiCast на 2-м и 5-м ходу);
//   2) целые партии ИИ против ИИ, где Math.random заменён на mulberry32(seed) — тот же поток, что Rng в Match;
//   3) статистику по 200 партиям (средняя длина, победы более сильной руки, камбэки).
// Запуск: node godot/tests/js_parity.js  → печатает сводку и пишет godot/tests/parity_js.json,
// который затем сверяет test_core.gd.
'use strict';
const fs = require('fs');
const path = require('path');
const vm = require('vm');

const HERE = __dirname;
const HTML = path.resolve(HERE, '../../web/index.html');
const src = fs.readFileSync(HTML, 'utf8');
const cases = JSON.parse(fs.readFileSync(path.join(HERE, 'parity_cases.json'), 'utf8'));
const SIM_GAMES = +(process.argv[2] || 200);

function cut(from, to) {
  const a = src.indexOf(from);
  const b = src.indexOf(to, a + 1);
  if (a < 0 || b < 0) throw new Error('не найден блок: ' + from);
  return src.slice(a, b);
}
const partRules = cut("const SUITS={", "/* =========================================================\n   ЗВУК");
const partBattle = cut("const sleep=ms=>", "function log(msg");
const partMul = cut("function mulberry32(a)", "\nconst SHOP_SECS");
const partQueue = cut("async function applyQueued(){", "function netOver(){").replace('async function applyQueued(){', 'async function applyQueuedOrig(){');

const stubs = `
const document={querySelector:()=>null,body:{classList:{add(){},remove(){}}}};
class V3{constructor(){} add(){return this;} clone(){return this;}}
const nodes=new Map();
const noop=()=>{};
const render=noop,renderHand=noop,renderStage=noop,renderTags=noop,makeBars=noop,float=noop,upd=noop,
  shakeFx=noop,flashHalo=noop,burst=noop,sfx=noop,dieFx=noop,log=noop,lungeFx=noop,camShake=noop,clearBars=noop,toast=noop;
const posOf=()=>null;
const castFx=async()=>{}, bolt=async()=>{}, boltPos=async()=>{};
const tween=()=>Promise.resolve();
const NET={};
`;

const harness = `
let SCHEDULE={};
async function netSync(k){S.queued=(SCHEDULE[k]||[]).slice();}
// ИИ-заклинания автоигрока (сторона p): копия aiCast с переставленными сторонами
async function aiCastP(){
  const i=S.p.hand.findIndex(k=>MAGIC[k].k==='spell'); if(i<0) return;
  const k=S.p.hand[i],M=MAGIC[k],A=S.teams.p,F=S.teams.e;
  let t=null;
  if(k==='guillotine') t=live(F).sort((a,b)=>a.hp/a.maxHp-b.hp/b.maxHp)[0];
  else if(M.t==='foe') t=live(F).sort((a,b)=>b.atk-a.atk)[0];
  else if(M.t==='ally') t=k==='surge'?live(A).filter(c=>c.mana<c.mm).sort((a,b)=>b.atk-a.atk)[0]:live(A).sort((a,b)=>a.hp/a.maxHp-b.hp/b.maxHp)[0];
  if(M.t&&!t) return;
  S.p.hand.splice(i,1);
  await castSpell('p',k,t);
}
async function applyQueued(){
  await applyQueuedOrig();
  if(S.pAi&&(S.step===2||S.step===5)&&S.p.hand.length) await aiCastP();
}
function mkBoard(arr,base){
  return arr.map((u,lane)=>u?{uid:base+lane,id:u.id,star:u.star,items:(u.items||[]).slice(),...(u.fed?{fed:{...u.fed}}:{})}:null);
}
function snapUnits(){
  const out=[];
  for(const tag of ['p','e']) S.teams[tag].forEach((c,lane)=>{ if(c) out.push((tag==='p'?lane:5+lane)+':'+c.hp+'/'+c.shield+'/'+c.atk+'/'+c.mana+'/'+(c.alive?1:0)); });
  return out.join(' ');
}
async function runBattle(cs){
  S={mode:'net',round:cs.round,diff:'normal',speed:99,p:newSide(),ai:newSide(),home:true,opp:{bot:true,allin:false,ghost:false,name:'x'},
     teams:null,step:0,spellsUsed:0,log:[],pendingSpells:[],queued:[],rng:mulberry32(cs.seed|0),pAi:false};
  S.p.board=mkBoard(cs.home,1); S.ai.board=mkBoard(cs.away,101); S.ai.hand=cs.away_hand.slice();
  SCHEDULE={};
  for(const sp of cs.spells){
    const tside=MAGIC[sp.key].t==='ally'?sp.side:MAGIC[sp.key].t==='foe'?(sp.side==='home'?'away':'home'):sp.side;
    (SCHEDULE[sp.after]??=[]).push({k:sp.key,caster:sp.side,tside,lane:Math.max(0,sp.lane)});
  }
  // home-заклинания идут раньше away (как S.queued у хозяина)
  for(const k in SCHEDULE) SCHEDULE[k].sort((a,b)=>(a.caster==='home'?0:1)-(b.caster==='home'?0:1));
  const res=await simulate();
  return {name:cs.name,outcome:res.pa&&!res.ea?'home':!res.pa&&res.ea?'away':'draw',steps:S.step,units:snapUnits()};
}
const handIdx=units=>HAND_ORDER.indexOf(teamInfo(units).hand);
async function simGame(seed){
  Math.random=mulberry32(seed);
  uidc=1;SCHEDULE={};
  S={mode:'net',round:1,diff:'normal',speed:99,p:newSide(),ai:newSide(),home:true,opp:{bot:true,allin:false,ghost:false,name:'x'},
     teams:null,step:0,spellsUsed:0,log:[],pendingSpells:[],queued:[],rng:null,pAi:true,allinCd:0,locked:false};
  const trace=[],battles=[];let minDiffP=0,minDiffE=0;
  let first=true;
  for(;;){
    // beginRound
    for(const [side,isAi] of [[S.p,false],[S.ai,true]]){
      if(first){side.gold=6;continue;}
      const interest=Math.min(5,Math.floor(side.gold/10)),sb=streakGold(side.streak);
      side.gold+=Math.max(0,5+interest+sb+(isAi?AIBONUS[S.diff]:0));addXp(side,2);
    }
    S.shop=rollShop(S.p.level,S.p);S.magicShop=[rollMagic(),rollMagic()];
    S.allin=false;S.ai.allin=false;first=false;
    // fight
    aiTurn(S.p);
    aiTurn(S.ai);
    if((S.ai.allinCd||0)<=S.round&&S.ai.hp+15<S.p.hp&&Math.random()<.6){S.ai.allin=true;S.ai.allinCd=S.round+3;}
    if(!S.allin&&(S.allinCd||0)<=S.round&&S.p.hp+15<S.ai.hp&&Math.random()<.6){S.allin=true;}
    S.rng=mulberry32(Math.floor(Math.random()*2147483647));
    const hp=handIdx(S.p.board.filter(Boolean)),he=handIdx(S.ai.board.filter(Boolean));
    const res=await simulate();
    // resolve (без сети и текстов)
    const base=1+Math.floor(S.round/3);
    const surv=t=>t.filter(c=>c&&c.alive).reduce((s,c)=>s+c.u.star+(c.d.c>=4?1:0),0);
    const myAllin=!!S.allin,oppAllin=!!S.ai.allin,oppStreak=S.ai.streak,myStreak=S.p.streak;
    let outcome='draw',dmgP=0,dmgE=0;
    if(res.pa&&!res.ea){outcome='win';dmgE=roundDamage(base,surv(res.A));if(myAllin)dmgE*=2;if(oppAllin)dmgE=Math.round(dmgE*1.5);}
    else if(!res.pa&&res.ea){outcome='lose';dmgP=roundDamage(base,surv(res.B));if(oppAllin)dmgP*=2;if(myAllin)dmgP=Math.round(dmgP*1.5);}
    else{dmgP=dmgE=roundDamage(base,0);}
    if(myAllin) S.allinCd=S.round+3;
    if(outcome==='win'&&oppStreak>=3){S.p.gold+=oppStreak;if(S.p.hand.length<5){S.p.hand.push(rollMagic());}}
    if(outcome==='lose'&&myStreak>=3) S.ai.gold+=myStreak;
    S.p.hp=Math.max(0,S.p.hp-dmgP);S.ai.hp=Math.max(0,S.ai.hp-dmgE);
    if(outcome==='win'){S.p.streak=S.p.streak>0?S.p.streak+1:1;S.ai.streak=S.ai.streak<0?S.ai.streak-1:-1;}
    else if(outcome==='lose'){S.ai.streak=S.ai.streak>0?S.ai.streak+1:1;S.p.streak=S.p.streak<0?S.p.streak-1:-1;}
    else{S.p.streak=0;S.ai.streak=0;}
    battles.push({hp,he,outcome});
    trace.push(S.p.hp+'-'+S.ai.hp);
    minDiffP=Math.min(minDiffP,S.p.hp-S.ai.hp);minDiffE=Math.min(minDiffE,S.ai.hp-S.p.hp);
    if(S.p.hp<=0||S.ai.hp<=0||S.round>=60) break;
    S.round++;
  }
  const winner=S.p.hp>S.ai.hp?'p':S.p.hp<S.ai.hp?'e':'draw';
  return {seed,rounds:S.round,hp_p:S.p.hp,hp_ai:S.ai.hp,winner,trace:trace.join(' '),battles,minDiffP,minDiffE};
}
function simStats(games){
  let rounds=0,strongerWins=0,decided=0,behind=0,comebacks=0;
  for(const g of games){
    rounds+=g.rounds;
    for(const b of g.battles){ if(b.hp!==b.he&&b.outcome!=='draw'){decided++; if((b.hp>b.he)===(b.outcome==='win')) strongerWins++;} }
    // камбэк: победитель в какой-то момент отставал на 20+ ОЗ
    const wasBehind=g.minDiffP<=-20||g.minDiffE<=-20;
    if(wasBehind) behind++;
    if((g.winner==='p'&&g.minDiffP<=-20)||(g.winner==='e'&&g.minDiffE<=-20)) comebacks++;
  }
  return {games:games.length,avg_rounds:rounds/games.length,stronger_hand_win_pct:100*strongerWins/Math.max(1,decided),
    decided_battles:decided,games_with_20hp_deficit:behind,comebacks,comeback_pct_of_deficit_games:100*comebacks/Math.max(1,behind),
    comeback_pct_of_all_games:100*comebacks/games.length};
}
(async()=>{
  const out={battles:[],games:[],stats:null};
  for(const cs of CASES.battles) out.battles.push(await runBattle(cs));
  for(const sd of CASES.game_seeds){const g=await simGame(sd);out.games.push({seed:g.seed,rounds:g.rounds,hp_p:g.hp_p,hp_ai:g.hp_ai,trace:g.trace});}
  const all=[];for(let sd=1;sd<=SIM_GAMES;sd++) all.push(await simGame(sd));
  out.stats=simStats(all);
  DONE(out);
})().catch(e=>FAIL(e));
`;

const ctx = {console, CASES: cases, SIM_GAMES, DONE: null, FAIL: null};
vm.createContext(ctx);
const code = stubs + partRules + '\n' + partMul + '\n' + partBattle + '\n' + partQueue + '\n' + harness;
new Promise((res, rej) => {
  ctx.DONE = res; ctx.FAIL = rej;
  vm.runInContext(code, ctx, {filename: 'kozyr-core.js'});
}).then(out => {
  fs.writeFileSync(path.join(HERE, 'parity_js.json'), JSON.stringify(out, null, 1));
  for (const b of out.battles) console.log(`battle ${b.name}: ${b.outcome} steps=${b.steps} | ${b.units}`);
  for (const g of out.games) console.log(`game ${g.seed}: rounds=${g.rounds} hp=${g.hp_p}-${g.hp_ai}`);
  console.log('stats', JSON.stringify(out.stats));
}).catch(e => { console.error(e); process.exit(1); });
