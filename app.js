'use strict';
// ClinicFlow prototype. The patient app, staff app and staff website all read and write this one in-page
// data set, which stands in for the shared backend/API. Nothing leaves the browser: no real texts, emails or logins.

// ---------- helpers ----------
const $=(s,r=document)=>r.querySelector(s), $$=(s,r=document)=>[...r.querySelectorAll(s)];
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const ic=(id,cls='ic')=>`<svg class="${cls}" aria-hidden="true"><use href="#i-${id}"/></svg>`;
const digits=s=>String(s||'').replace(/\D/g,'');
// a short message; pass undo to offer a 6-second Undo for an action that can't otherwise be taken back
function toast(which,msg,undo){
  const el=$('#'+which+'-toast');el.replaceChildren(msg);
  if(undo){const b=document.createElement('button');b.textContent='Undo';b.onclick=()=>{clearTimeout(el._t);el.classList.remove('show','act');undo()};el.append(b)}
  el.classList.toggle('act',!!undo);el.classList.add('show');clearTimeout(el._t);el._t=setTimeout(()=>el.classList.remove('show','act'),undo?6000:2800);
}
// re-rendering replaces innerHTML; put focus (and the caret) back where the person was
function keepFocus(fn){
  const a=document.activeElement;if(!a||a===document.body)return fn();
  const id=a.id,oc=a.getAttribute('onclick');let sel=null;try{if(a.setSelectionRange&&a.selectionStart!=null)sel=[a.selectionStart,a.selectionEnd]}catch(e){}
  const r=fn(),now=document.activeElement;
  if(now===a&&a.isConnected&&a.offsetParent)return r;
  if(now&&now!==document.body&&now!==a)return r;
  const n=(id&&document.getElementById(id))||(oc&&[...document.querySelectorAll('[onclick]')].find(x=>x.getAttribute('onclick')===oc&&x.offsetParent));
  if(n&&n.offsetParent){n.focus({preventScroll:true});if(sel)try{n.setSelectionRange(sel[0],sel[1])}catch(e){}}
  return r;
}
function setCurrent(btns,test){btns.forEach(b=>test(b)?b.setAttribute('aria-current','page'):b.removeAttribute('aria-current'))}
function showErr(id,msg){const el=$('#'+id);if(!el)return;el.textContent=msg||'';el.hidden=!msg}
function initials(n){return String(n).replace('Dr. ','').replace(',','').split(' ').filter(Boolean).map(w=>w[0]).slice(0,2).join('').toUpperCase()}
function newCode(){return String(Math.floor(100000+Math.random()*900000))}

// ---------- clock: the prototype's day is Tue Sep 29, starting at 9:41 am ----------
const T0=Date.now(), BASE_SEC=9*3600+41*60, CAL_BASE='2026-09-29';
function clock(sec=true){const s=BASE_SEC+Math.floor((Date.now()-T0)/1000),h=Math.floor(s/3600)%24,m=Math.floor(s/60)%60;return `${String(h).padStart(2,'0')}:${String(m).padStart(2,'0')}${sec?':'+String(s%60).padStart(2,'0'):''}`}
function clock12(){const [h,m]=clock(false).split(':').map(Number);return `${h>12?h-12:h}:${String(m).padStart(2,'0')} ${h>=12?'pm':'am'}`}
const TIMES=['9:00','9:30','10:00','10:30','11:00','11:30','1:00','1:30','2:00','2:30','3:00','3:30','4:00','4:30'];
const tIdx=t=>TIMES.indexOf(t);
const ampm=t=>{const h=+String(t).split(':')[0];return `${t} ${h>=9&&h<12?'am':'pm'}`};
const band=t=>{const i=tIdx(t);return i<=5?'morning':i<=11?'afternoon':'after4'};
const slotMin=t=>{let [h,m]=String(t).split(':').map(Number);if(h<9)h+=12;return h*60+m};
const nowMin=()=>Math.floor((BASE_SEC+(Date.now()-T0)/1000)/60);
const frTime=t=>{const m=slotMin(t);return `${Math.floor(m/60)} h ${String(m%60).padStart(2,'0')}`};
const to12=hhmm=>{const [h,m]=String(hhmm).split(':').map(Number);return `${h>12?h-12:h}:${String(m).padStart(2,'0')} ${h>=12?'pm':'am'}`};
// tickets sort as numbers: A-9 comes before A-13
const tnum=t=>+digits(t)||0;

// ---------- shared data (the "database") ----------
const ROLES={admin:'Admin',frontdesk:'Front desk',clinician:'Clinician',support:'Support'};
const PATIENT='Priya Raman (patient)', SYSTEM='System';
const state={
  clins:[
    {id:'osei',name:'Dr. Kwame Osei',short:'Dr. Osei',role:'Physiotherapist',roleFr:'Physiothérapeute',hours:'Mon–Fri 9–5'},
    {id:'lam',name:'Mei Lam, PT',short:'M. Lam',role:'Physiotherapist',roleFr:'Physiothérapeute',hours:'Tue, Thu, Sat 9–2'},
    {id:'daoud',name:'Dr. Rania Daoud',short:'Dr. Daoud',role:'Chiropractor',roleFr:'Chiropraticienne',hours:'Thu only',visiting:true},
    {id:'walk',name:'Walk-in room',short:'Walk-in',role:'Same-day visits',roleFr:'Visites sans rendez-vous',hours:'Mon–Fri 9–5',room:true},
  ],
  services:[
    {name:'Physiotherapy · follow-up',fr:'Physiothérapie · suivi',short:'Physio follow-up',dur:30,buf:0,online:true,who:'Returning patients',whoFr:'Patients déjà suivis',form:'Reason',clins:['osei','lam']},
    {name:'Physiotherapy · initial assessment',fr:'Physiothérapie · évaluation initiale',short:'Initial assessment',dur:45,buf:5,online:true,who:'New and returning',whoFr:'Nouveaux patients et patients suivis',form:'Contact, consent, reason',clins:['osei','lam']},
    {name:'Chiropractic · adjustment',fr:'Chiropratique · ajustement',short:'Chiro adjustment',dur:20,buf:5,online:true,who:'New and returning',whoFr:'Nouveaux patients et patients suivis',form:'Contact, consent',clins:['daoud']},
    {name:'Walk-in · same day',short:'Walk-in',dur:15,buf:0,online:false,who:'Front desk only',form:'Contact',clins:['walk']},
  ],
  pLang:'en',
  // unavailable time: a single time, "*" for all day, or "2:00+" for that time onward
  blocks:[{clin:'lam',time:'11:00',type:'Break'},{clin:'osei',time:'1:00',type:'Break'},{clin:'daoud',time:'*',type:'Not in'},{clin:'lam',time:'2:00+',type:'Not in'}],
  timeoff:[{clin:'osei',type:'Vacation',when:'Oct 12–16'},{clin:'osei',type:'Break',when:'Tue 1:00'},{clin:'lam',type:'Break',when:'Tue 11:00'},{clin:'daoud',type:'Not in',when:'Mon–Wed, Fri'}],
  blockTypes:[{name:'Break',scope:'Each clinician'},{name:'Not in',scope:'Each clinician'},{name:'Admin time',scope:'Each clinician'},{name:'Vacation',scope:'Each clinician'},{name:'Statutory holiday',scope:'Whole clinic'}],
  // today's appointments (Tue Sep 29)
  queue:[
    {id:1,name:'Priya Raman',clin:'osei',time:'9:00',svc:'Physio follow-up',svcFull:'Physiotherapy · follow-up',status:'booked',forms:false,phone:'0142',mine:true},
    {id:2,name:'Marcus Chen',clin:'osei',time:'9:30',svc:'Physio follow-up',status:'late',forms:true,phone:'2201'},
    {id:3,name:'An Nguyen',clin:'lam',time:'9:00',svc:'Initial assessment',status:'invisit',forms:true,ticket:'A-14',since:8,phone:'6634'},
    {id:4,name:'Walk-in #12',clin:'walk',time:'9:00',svc:'Walk-in',status:'waiting',forms:true,ticket:'A-13',since:14},
    {id:5,name:'Lucie Fortin',clin:'osei',time:'10:00',svc:'Physio follow-up',status:'confirmed',forms:true,phone:'7788'},
    {id:6,name:'Raj Singh',clin:'lam',time:'10:00',svc:'Physio follow-up',status:'booked',forms:false,phone:'5530'},
    {id:7,name:'Jordan Tremblay',clin:'osei',time:'11:00',svc:'Physio follow-up',status:'confirmed',forms:true,phone:'4410'},
    {id:8,name:'Daniel Okafor',clin:'osei',time:'11:30',svc:'Physio follow-up',status:'booked',forms:true,phone:'9921'},
    {id:9,name:'Tara Brown',clin:'lam',time:'11:30',svc:'Physio follow-up',status:'confirmed',forms:true,phone:'3307'},
    {id:10,name:'Ella Moore',clin:'lam',time:'1:30',svc:'Initial assessment',status:'confirmed',forms:false,phone:'1185'},
    {id:11,name:'Hana Sato',clin:'osei',time:'2:00',svc:'Physio follow-up',status:'confirmed',forms:true,phone:'2290'},
    {id:12,name:'Victor Diaz',clin:'osei',time:'3:00',svc:'Initial assessment',status:'booked',forms:false,phone:'6071'},
  ],
  nextId:20, nextTicket:15, walkins:12,
  intake:{},
  locks:{},
  freed:[{id:'F1',clin:'osei',time:'10:30',reason:'Omar Haddad cancelled',freedAt:T0-11*60000,freedClock:'09:28',status:'offered',offers:[{wl:'w1',name:'Jordan Tremblay',after:130,sentClock:'09:30',status:'holding'}]}],
  waitlist:[
    {id:'w1',name:'Jordan Tremblay',svc:'Physio',clin:'osei',days:['Mon','Tue','Wed','Thu','Fri'],times:['morning'],status:'offered',priority:false,joined:'Sep 24'},
    {id:'w2',name:'Amara Bello',svc:'Chiro',clin:'any',days:['Tue','Wed'],times:['morning','afternoon','after4'],status:'waiting',priority:true,joined:'Sep 25'},
    {id:'w3',name:'Sam Kowalski',svc:'Physio',clin:'any',days:['Sat','Sun'],times:['morning','afternoon'],status:'waiting',priority:false,joined:'Sep 26'},
  ],
  wlPrefs:{days:['Mon','Tue','Thu'],times:['morning','after4'],clin:'any'},
  pendingOffer:null,
  recovery:{total:17,refilled:12},
  rules:{cancelWindow:24,order:'First come, first served (staff can pin priority)',hold:15,cutoff:'60 min before slot',remind48:true,remind24:true},
  booking:{mode:'new',service:'Physiotherapy · follow-up',clin:'osei',time:null,who:'me'},
  otp:{code:null,phone:'',pending:{},target:null},
  consent:{sms:true,at:'Sep 22, 2026'},
  pSigned:true, largeText:false, findFilter:'accepting',
  family:[{id:'f1',name:'Arjun Raman',rel:'Child',dob:'2017-04-12'}], famFrom:'profile',
  history:[
    {date:'Sep 15, 2026',svc:'Physiotherapy · follow-up',clin:'Dr. Kwame Osei',clinic:'Maple Grove Clinic',fee:95,owing:0,who:'Priya Raman'},
    {date:'Sep 1, 2026',svc:'Physiotherapy · initial assessment',clin:'Dr. Kwame Osei',clinic:'Maple Grove Clinic',fee:130,owing:40,who:'Priya Raman'},
    {date:'Aug 20, 2026',svc:'Chiropractic · adjustment',clin:'Dr. Rania Daoud',clinic:'Maple Grove Clinic',fee:70,owing:0,who:'Arjun Raman'},
    {date:'Jun 11, 2026',svc:'Physiotherapy · follow-up',clin:'Sam Whitlock, PT',clinic:'Lakeshore Physio',fee:90,owing:0,who:'Priya Raman'},
  ],
  directory:[
    {ini:'MG',name:'Maple Grove Clinic',dist:0.8,services:'Physiotherapy, chiropractic',accepting:true,today:true,next:'next opening today 2:30 pm',self:true},
    {ini:'DF',name:'Dundas Family Health',dist:1.6,services:'Family practice, walk-in',accepting:true,today:true,next:'next opening today 4:00 pm'},
    {ini:'LP',name:'Lakeshore Physio',dist:2.1,services:'Physiotherapy',accepting:true,today:false,next:'next opening Wed 9:00 am'},
    {ini:'QW',name:'Queen West Rehab',dist:3.4,services:'Rehab, massage',accepting:false,today:false,next:'waitlist only'},
    {ini:'HM',name:'Harbour Mind Wellness',dist:4.2,services:'Mental health, counselling',accepting:true,today:false,next:'next opening Fri 1:00 pm'},
  ],
  notice:'Parking lot B is closed this week. Street parking on Elm Ave is free for 2 hours.',
  pNotifs:[
    {t:'Reminder: Physio today 9:00 am with Dr. Osei. Tap to confirm, or reschedule.',s:'Mon 9:00 am · push, then text',k:'info',act:'confirm'},
    {t:'Please complete your reason-for-visit form before your visit.',s:'Mon 9:01 am · text',k:'warn',act:'intake'},
    {t:'Reminder: Physio on Tue Sep 29 at 9:00 am with Dr. Osei.',s:'Sun 9:00 am · push',k:'info'},
    {t:'Booked: Physio, Tue Sep 29, 9:00 am. Manage your visit any time from this link.',s:'Sep 22 · text and email',k:'good'},
  ],
  sAlerts:[
    {t:'Freed 10:30 am slot (Dr. Osei) offered to Jordan Tremblay 2 min 10 s after the cancellation.',s:'9:30 am',k:'warn'},
    {t:'Omar Haddad cancelled 10:30 am with Dr. Osei.',s:'9:28 am',k:'warn'},
    {t:'Marcus Chen is late for 9:30 am and not checked in.',s:'9:41 am',k:'crit'},
    {t:'Intake nudges sent to 5 patients; 2 fell back to text.',s:'8:30 am',k:'info'},
  ],
  missedFilter:'open',
  missed:[
    {id:1,date:'Sep 28',time:'2:40 pm',name:'Tomás Rivera',clin:'Dr. Osei',svc:'Physio follow-up',reminder:'Delivered, no reply',prior:2,status:'open'},
    {id:2,date:'Sep 25',time:'9:00 am',name:'Grace Liu',clin:'M. Lam',svc:'Initial assessment',reminder:'Confirmed by text',prior:0,status:'open'},
    {id:3,date:'Sep 22',time:'11:30 am',name:'Omar Haddad',clin:'Dr. Osei',svc:'Physio follow-up',reminder:'Text failed, email sent',prior:0,status:'rebooked'},
    {id:4,date:'Sep 17',time:'4:00 pm',name:'Elena Petrova',clin:'Dr. Daoud',svc:'Chiro adjustment',reminder:'Delivered, no reply',prior:1,status:'excused'},
    {id:5,date:'Sep 9',time:'10:00 am',name:'Ben Carter',clin:'M. Lam',svc:'Physio follow-up',reminder:'Confirmed by push',prior:0,status:'contacted'},
  ],
  deliveries:[
    {t:'Mon 09:00',to:'Priya Raman',msg:'Reminder, 24 h',ch:'Push, then text',out:'Push not opened in 30 min; text delivered'},
    {t:'Mon 09:00',to:'Lucie Fortin',msg:'Reminder, 24 h',ch:'Push',out:'Delivered · confirmed'},
    {t:'Sun 09:00',to:'Priya Raman',msg:'Reminder, 48 h',ch:'Push, then email',out:'Delivered'},
    {t:'Sun 09:00',to:'Raj Singh',msg:'Reminder, 48 h',ch:'Push, then email',out:'Email delivered · no reply'},
  ],
  upcoming:[{name:'Grace Liu',when:'Wed Sep 30 9:30 am',h:24},{name:'Ben Carter',when:'Wed Sep 30 1:00 pm',h:24},{name:'Nadia Petrov',when:'Wed Sep 30 3:30 pm',h:24},{name:'Owen Park',when:'Thu Oct 1 10:00 am',h:48},{name:'Amara Bello',when:'Thu Oct 1 11:30 am',h:48}],
  remindersRun:false,
  users:[
    {id:'dana',name:'Dana Whitfield',role:'admin',signin:'Passkey + 2FA',last:'Now'},
    {id:'luis',name:'Luis Herrera',role:'frontdesk',signin:'Passkey · Face ID on the staff app',last:'4 min ago'},
    {id:'osei',name:'Dr. Kwame Osei',role:'clinician',clin:'osei',signin:'Face ID (staff app)',last:'11 min ago'},
    {id:'lam',name:'Mei Lam, PT',role:'clinician',clin:'lam',signin:'Face ID (staff app)',last:'Yesterday'},
    {id:'temp',name:'Jo Tan (temp agency)',role:'support',signin:'One-time code, expires Oct 3',last:'2 d ago'},
  ],
  staffUser:'luis', webUser:'dana', staffPick:'luis', staffCode:null, webCode:null, pCode:null,
  filter:'all', schedClin:'osei', selectedPatient:1,
  audit:[
    {t:'09:30:12',actor:SYSTEM,action:'waitlist.offer.sent',record:'SLOT osei 10:30',detail:'Offered to Jordan Tremblay · push + text · hold 15 min · 2 min 10 s after cancellation'},
    {t:'09:28:04',actor:'Omar Haddad (patient)',action:'appointment.cancel',record:'APT-20918',detail:'Cancelled from the text link · inside the 24 h window · recorded as late cancellation'},
    {t:'09:02:33',actor:'Luis Herrera (Front desk)',action:'appointment.create',record:'APT-20940',detail:'Walk-in #12 · slot lock held 41 s'},
    {t:'08:30:00',actor:SYSTEM,action:'notification.sent',record:'5 records',detail:'Intake nudge · push 5, text fallback 2, delivered 5'},
    {t:'08:12:40',actor:'Luis Herrera (Front desk)',action:'auth.signin',record:'USER-luis',detail:'Staff app · Face ID'},
    {t:'Mon 17:12',actor:'Dana Whitfield (Admin)',action:'role.update',record:'USER-temp',detail:'Support: Reports → none (was: today)'},
    {t:'Mon 16:40',actor:'Dr. Kwame Osei (Clinician)',action:'intake.view',record:'APT-20931',detail:'Viewed reason-for-visit · own patient'},
    {t:'Mon 09:15',actor:'Dana Whitfield (Admin)',action:'settings.update',record:'CLINIC',detail:'Cancellation window 48 h → 24 h'},
  ],
  dbTests:[], tplPick:'reminder24',
  tpls:{
    reminder24:{label:'Reminder, 24 h before',text:'Hi {first_name}, reminder: {service} with {clinician} tomorrow at {time}, Maple Grove Clinic. Tap to confirm: {link}. Need to change it? Same link. Reply STOP to opt out.'},
    cancelPatient:{label:'Cancellation, patient cancelled',text:'Hi {first_name}, your {service} on {date} at {time} is cancelled. Book again any time: {link}. Reply STOP to opt out.'},
    cancelClinic:{label:'Cancellation, clinic cancelled',text:"Hi {first_name}, we're sorry: we had to cancel your {service} with {clinician} on {date} at {time} ({reason}). You're first in line for a new time: {link}"},
    missed:{label:'Missed visit follow-up',text:'Hi {first_name}, we missed you at {time} today. No problem, life happens. Pick a new time that suits you: {link}. Reply STOP to opt out.'},
  },
  calView:'day',
  setup:{step:5,done:[1,2,3,4],start:Date.now()-38*60000,finished:null,profile:{name:'Maple Grove Clinic',address:'214 Elm Ave, Toronto ON',phone:'+1 416 555 0100',brand:'blue'},existing:'fresh',listed:true},
  lastChange:Date.now(),
};
// each status has its own colour (tokens.css --st-*); "out" draws an outlined dot: the patient isn't here yet
const STATUS={booked:['s-booked out','Booked'],confirmed:['s-confirmed out','Confirmed'],checked:['s-checked','Checked in'],waiting:['s-waiting','Waiting'],invisit:['s-invisit','In visit'],done:['s-done','Complete'],late:['s-late out','Late'],noshow:['s-noshow out','No-show'],cancelled:['s-cancelled out','Cancelled']};
const ACTIVE=q=>!['cancelled','noshow'].includes(q.status);
const clinById=id=>state.clins.find(c=>c.id===id)||{name:id,short:id};
const svcByName=n=>state.services.find(s=>s.name===n)||state.services[0];
const pill=st=>{const [k,l]=STATUS[st]||['',st];return `<span class="pill st ${k}">${l}</span>`};
const PKIND={info:'Reminder',warn:'To do',good:'Update',crit:'Urgent',mute:'Notice'}, SKIND={info:'Update',warn:'Change',good:'Done',crit:'Urgent',mute:'Notice'};
const touch=()=>{state.lastChange=Date.now()};

// ---------- audit log: every change goes through here ----------
function logAudit(actor,action,record,detail){state.audit.unshift({t:clock(),actor,action,record,detail});touch()}
const userById=id=>state.users.find(u=>u.id===id);
const staffUser=()=>userById(state.staffUser), webUser=()=>userById(state.webUser);
const actorOf=u=>u?`${u.name} (${ROLES[u.role]})`:'Signed-out user';
function alertStaff(t,k='info'){state.sAlerts.unshift({t,s:clock12(),k})}
function notifyPatient(t,s,k='info',act){state.pNotifs.unshift({t,s:`${clock12()} · ${s}`,k,act})}
function deliver(to,msg,ch,out){state.deliveries.unshift({t:clock(false),to,msg,ch,out})}

// ---------- schedule queries ----------
function blockAt(clin,time){return state.blocks.find(b=>b.clin===clin&&(b.time==='*'||b.time===time||(b.time.endsWith('+')&&tIdx(time)>=tIdx(b.time.slice(0,-1)))))}
function apptAt(clin,time){return state.queue.find(q=>q.clin===clin&&q.time===time&&ACTIVE(q))}
const lockKey=(clin,time)=>clin+'|'+time;
function lockAt(clin,time){const l=state.locks[lockKey(clin,time)];return l&&l.until>Date.now()?l:null}
function freedAt(clin,time){return state.freed.find(f=>f.clin===clin&&f.time===time&&f.status!=='filled')}
// what a given viewer can do with a slot
function slotState(clin,time,viewer,ignoreId){
  if(blockAt(clin,time))return 'blocked';
  const a=apptAt(clin,time);if(a&&a.id!==ignoreId)return 'taken';
  const l=lockAt(clin,time);if(l&&l.owner!==viewer)return 'held';
  const f=freedAt(clin,time);if(f&&f.offers.some(o=>o.status==='holding'&&!(viewer==='patient'&&o.wl===myWl()?.id)))return 'offered';
  return f?'freed':'free';
}
function acquireLock(clin,time,owner,secs){for(const k in state.locks)if(state.locks[k].owner===owner)delete state.locks[k];const l=lockAt(clin,time);if(l&&l.owner!==owner)return false;state.locks[lockKey(clin,time)]={owner,until:Date.now()+secs*1000};touch();return true}
function releaseLocks(owner){for(const k in state.locks)if(state.locks[k].owner===owner)delete state.locks[k]}
// the single write path for new appointments: a unique (clinician, start time) rule, checked atomically
function commitBooking(entry,owner){
  if(blockAt(entry.clin,entry.time)||apptAt(entry.clin,entry.time))return false;
  const l=lockAt(entry.clin,entry.time);if(l&&l.owner!==owner)return false;
  entry.id=state.nextId++;state.queue.push(entry);delete state.locks[lockKey(entry.clin,entry.time)];
  const f=freedAt(entry.clin,entry.time);if(f){f.status='filled';f.filledBy=entry.name;state.recovery.refilled++}
  touch();return true;
}
function capacity(clin){return TIMES.filter(t=>!blockAt(clin,t)).length}
function bookedCount(clin){return state.queue.filter(q=>q.clin===clin&&ACTIVE(q)).length}
function waitMins(q){return (q.since||0)+Math.floor((Date.now()-(q.waitStart||T0))/60000)}

// ---------- waitlist and freed-slot recovery ----------
function myWl(){return state.waitlist.find(w=>w.mine&&w.status!=='booked')}
function wlMatches(w,f){
  const svcClins={Physio:['osei','lam'],Chiro:['daoud']}[w.svc]||[];
  return svcClins.includes(f.clin)&&(w.clin==='any'||w.clin===f.clin)&&w.days.includes('Tue')&&w.times.includes(band(f.time));
}
function freeSlot(clin,time,reason){
  const f={id:'F'+(state.nextId++),clin,time,reason,freedAt:Date.now(),freedClock:clock(false),status:'open',offers:[]};
  state.freed.unshift(f);state.recovery.total++;
  alertStaff(`${reason}: ${ampm(time)} with ${clinById(clin).short} is free. Offering it to the waitlist.`,'warn');
  setTimeout(()=>{cascade(f);renderAll()},1200);
  return f;
}
function cascade(f){
  if(f.status==='filled')return;
  const tried=f.offers.map(o=>o.wl);
  const next=state.waitlist.filter(w=>w.status==='waiting'&&!tried.includes(w.id)&&wlMatches(w,f)).sort((a,b)=>(b.priority-a.priority))[0];
  if(!next){f.status='open';alertStaff(`No waitlist match for ${ampm(f.time)} with ${clinById(f.clin).short}. It's open for online booking.`,'info');touch();return}
  const after=Math.max(1,Math.round((Date.now()-f.freedAt)/1000));
  f.offers.push({wl:next.id,name:next.name,after,sentClock:clock(false),status:'holding'});f.status='offered';next.status='offered';
  const ok=after<300;
  alertStaff(`Freed ${ampm(f.time)} slot (${clinById(f.clin).short}) offered to ${next.name} ${fmtSecs(after)} after it opened${ok?' (target under 5 min)':''}.`,'warn');
  deliver(next.name,'Waitlist offer','Push + text','Delivered · holding 15 min');
  logAudit(SYSTEM,'waitlist.offer.sent','SLOT '+f.clin+' '+f.time,`Offered to ${next.name} · push + text · hold ${state.rules.hold} min · ${fmtSecs(after)} after the slot opened`);
  if(next.mine){state.pendingOffer=f.id;notifyPatient(`A slot opened: Tue Sep 29, ${ampm(f.time)} with ${clinById(f.clin).name}. It's held for you for 15 minutes.`,'push + text','good','offer')}
}
function fmtSecs(s){return s<60?`${s} s`:`${Math.floor(s/60)} min ${s%60} s`}

// ---------- surfaces and routing ----------
const hints={
  patient:'Book as a guest with a phone code, confirm from a reminder, fill the form, check in and follow your place in the queue. Staff actions show up here instantly.',
  staff:'Sign in as different roles to see what each can do. Arrive, add to queue, call in and complete patients; answer waitlist offers.',
  web:'Run the clinic: calendar with slot locking, check-in tablet, waitlist recovery, reminders, roles, audit log, reports and setup. Sign out to switch roles.'};
function surface(id,btn){$$('.stage').forEach(s=>s.classList.toggle('active',s.id==='stage-'+id));$$('.switch button').forEach(b=>b.setAttribute('aria-selected',b===btn));$('#hint').textContent=hints[id];cur.surface=id;syncHash();renderAll()}
const TAB_OF={book2:'book',book3:'book',otp:'book',family:'profile',history:'profile',signin:'profile'};
function showScreen(root,id){
  const prev=$('.screen.active',root),moving=prev&&prev.dataset.s!==id,hadFocus=prev&&prev.contains(document.activeElement);
  $$('.screen',root).forEach(s=>s.classList.toggle('active',s.dataset.s===id));
  setCurrent($$('.tabbar button',root.parentElement),b=>b.dataset.tab===(TAB_OF[id]||id));
  const a=$('.screen.active',root);if(!a||!moving)return;a.scrollTop=0;
  // a keyboard or screen-reader user lands on the new screen's heading, not on <body>
  if(hadFocus){const h=$('h2',a);if(h){h.tabIndex=-1;h.focus({preventScroll:true})}}
}
const NEEDS_SIGNIN=['home','appt','notifs','profile','history','family','checkin','intake','waitlist','offer'];
function pgo(id){if(!state.pSigned&&NEEDS_SIGNIN.includes(id))id='signin';showScreen($('#p-screens'),id);cur.patient=id;syncHash();renderPatient()}
function sgo(id){if(!state.staffUser)id='login';else if(!staffTabs().includes(id)&&!['patient'].includes(id))id='queue';showScreen($('#s-screens'),id);cur.staff=id;syncHash();renderStaff()}
function wgo(id,btn){if(!state.webUser){cur.web=id;renderWeb();return}if(!webPages().includes(id))id=webPages()[0];$$('.page').forEach(p=>p.classList.toggle('active',p.dataset.p===id));setCurrent($$('.side button'),b=>b.dataset.p===id);if(cur.web!==id)$('.main').scrollTop=0;cur.web=id;syncHash();renderWeb()}
const cur={surface:'patient',patient:'home',staff:'queue',web:'dash',calDate:CAL_BASE};
const REOPEN_AS={confirmed:'home',offer:'home',otp:'book3',book2:'book',book3:'book'};
function syncHash(){const h='#'+cur.surface+'/'+cur[cur.surface]+(cur.surface==='web'&&cur.web==='cal'?'/'+cur.calDate:'');if(location.hash!==h)history.replaceState(null,'',h)}
function openFromHash(){
  const [s,id,day]=location.hash.slice(1).split('/'),i=['patient','staff','web'].indexOf(s);
  if(s==='web'&&id==='cal'&&/^\d{4}-\d{2}-\d{2}$/.test(day||''))cur.calDate=day;
  if(i<0)return syncHash();
  surface(s,$$('.switch button')[i]);
  if(s==='patient'){const t=REOPEN_AS[id]||id;if($(`#p-screens [data-s="${t}"]`))pgo(t)}
  else if(s==='staff'&&$(`#s-screens [data-s="${id}"]`))sgo(id);
  else if(s==='web'&&$(`.page[data-p="${id}"]`))wgo(id);
}
window.addEventListener('hashchange',openFromHash);

// ---------- patient app ----------
function me(){const mine=state.queue.filter(q=>q.mine);return mine.find(q=>!['cancelled','noshow','done'].includes(q.status))||mine[mine.length-1]}
function whoName(){const f=state.family.find(f=>f.id===state.booking.who);return f?f.name:'Priya Raman'}
const forLabel=name=>name&&name!=='Priya Raman'?' · for '+name.split(' ')[0]:'';
const niceDate=iso=>iso?new Date(iso+'T00:00').toLocaleDateString('en-CA',{month:'short',day:'numeric',year:'numeric'}):'date of birth not set';
function smsBanner(text){const el=$('#p-sms');el.innerHTML=`<b>Messages · now · tap to dismiss</b><span>${esc(text)}</span>`;el.hidden=false;clearTimeout(el._t);el._t=setTimeout(()=>el.hidden=true,6000)}
// tapping the incoming text dismisses it; on the code step it fills the code, like the phone's own autofill
function smsTap(){const el=$('#p-sms');el.hidden=true;if(cur.patient==='otp'&&state.otp.code){fillCode();$$('#p-otp input')[5].focus()}}

// ---------- English / French for the screens anonymous patients use: the booking link and the check-in tablet ----------
const PL={
  en:{bookTitle:'Book a visit',bookIntro:"You opened Maple Grove Clinic's booking link. No account or password needed.",whoFor:'Who is this visit for?',step1:'Step 1 of 4 · Service',continue:'Continue',me:'Me',addSomeone:'+ Add',
    book2Title:'Who and when',book2Resched:'Pick a new time',step2:'Step 2 of 4 · Clinician and time',clinician:'Clinician',day:'Tuesday, Sep 29',anyClin:'First available',anyRole:'Any clinician',notTue:'not in on Tuesdays',
    slotNote:'Dashed times were freed by a cancellation. Crossed-out times are taken or unavailable.',slotNoteOff:'This clinician is not in on Tuesdays. Join the waitlist to hear about other days.',joinWl:'Nothing works? Join the waitlist',move:'Move my visit',
    held:'{time} with {who} is held for you for {left}',holdExpired:'Your hold on that time ran out. Pick a time again.',pickTime:'Choose a time to continue.',slotBusy:'Someone at the front desk is booking that time right now. Pick another time.',slotGone:'Someone booked that time a moment ago. Pick another time.',
    unavailable:'unavailable',taken:'taken',heldOther:'being booked by someone else',
    details:'Your details',step3:'Step 3 of 4 · Contact',fullName:'Full name',mobile:'Mobile number',email:'Email (optional)',
    smsConsent:'Text me reminders and waitlist offers. Message rates may apply. Reply STOP to opt out. Optional: without it we use push and email.',policy:'I agree to the 24-hour cancellation policy.',sendCode:'Send verification code',minData:'We ask for only your name and mobile number. Up to 2 unconfirmed bookings per number per day.',
    errName:'Enter your full name.',errPhone:'Enter a mobile number with area code, for example 416 555 0142.',errPolicy:'Please agree to the cancellation policy to book.',errLimit:'This number already has 2 unconfirmed bookings today. Confirm one with its code, or call the clinic at 416 555 0100.',
    verify:'Verify your phone',step4:'Step 4 of 4 · Code',otpTo:'We texted a 6-digit code to {phone}. It expires in 10 minutes.',confirmBooking:'Confirm booking',resend:'Resend code',summary:'Summary',errDigits:'Enter all 6 digits of the code.',errCode:"That code doesn't match. Check the text message and try again.",newCode:'New code sent',
    booked:"You're booked",bookedFor:'{name} is booked',bookedSub:"Confirmation sent by text and email. The link in it signs you in, so there's no password to remember.",next:'What happens next',calendar:'Add to my calendar',calendarAdded:'Added to your calendar. Changes and cancellations update it automatically.',done:'Done',
    forWho:'For {name}',dayShort:'Tue Sep 29',timeNotChosen:'time not chosen',now:'Now',today:'Today',fill:'Fill',form:'Reason for visit form',formSub:'2 minutes · helps the front desk plan',
    noReminder:'No reminders needed',noReminderSub:'Your visit is today. We send a push when check-in opens.',checkin:'Check in from your phone',checkinSub:'Opens 1 hour before, within 200 m of the clinic',
    k_welcome:'Welcome to {name}',k_intro:"Check in for today's visit. Enter the last 4 digits of your phone number.",k_clear:'Clear',k_del:'Delete',k_err4:'Enter the last 4 digits of your phone number.',k_none:"We couldn't find a visit today for that number. Please see the front desk.",
    k_isYou:'Is this you?',k_with:'{time} with {who}',k_notMe:"That's not me",k_privacy:'Only initials are shown here, for privacy.',k_done:"You're checked in",k_ticket:'Your ticket number. Please take a seat; the screen will call this number.',k_finish:'Done'},
  fr:{bookTitle:'Prendre rendez-vous',bookIntro:'Vous avez ouvert le lien de réservation de la Maple Grove Clinic. Aucun compte ni mot de passe requis.',whoFor:'Pour qui est ce rendez-vous?',step1:'Étape 1 sur 4 · Service',continue:'Continuer',me:'Moi',addSomeone:'+ Ajouter',
    book2Title:'Avec qui et quand',book2Resched:'Choisir une nouvelle heure',step2:'Étape 2 sur 4 · Professionnel et heure',clinician:'Professionnel',day:'Mardi 29 septembre',anyClin:'Premier disponible',anyRole:"N'importe quel professionnel",notTue:'absent le mardi',
    slotNote:'Les heures en pointillé ont été libérées par une annulation. Les heures barrées sont prises ou non disponibles.',slotNoteOff:"Ce professionnel est absent le mardi. Inscrivez-vous à la liste d'attente pour d'autres journées.",joinWl:"Aucune heure ne convient? Liste d'attente",move:'Déplacer mon rendez-vous',
    held:'{time} avec {who} : réservé pour vous pendant {left}',holdExpired:'Votre réservation temporaire a expiré. Choisissez une heure de nouveau.',pickTime:'Choisissez une heure pour continuer.',slotBusy:"Quelqu'un à l'accueil réserve cette heure en ce moment. Choisissez une autre heure.",slotGone:"Quelqu'un vient de réserver cette heure. Choisissez une autre heure.",
    unavailable:'non disponible',taken:'prise',heldOther:"en cours de réservation par quelqu'un d'autre",
    details:'Vos coordonnées',step3:'Étape 3 sur 4 · Coordonnées',fullName:'Nom complet',mobile:'Numéro de cellulaire',email:'Courriel (facultatif)',
    smsConsent:"Envoyez-moi des rappels et des offres de la liste d'attente par texto. Des frais de messagerie peuvent s'appliquer. Répondez STOP pour vous désabonner. Facultatif : sinon, nous utilisons les notifications et le courriel.",policy:"J'accepte la politique d'annulation de 24 heures.",sendCode:'Envoyer le code de vérification',minData:'Nous demandons seulement votre nom et votre numéro de cellulaire. Maximum de 2 réservations non confirmées par numéro et par jour.',
    errName:'Entrez votre nom complet.',errPhone:"Entrez un numéro de cellulaire avec l'indicatif régional, par exemple 416 555 0142.",errPolicy:"Veuillez accepter la politique d'annulation pour réserver.",errLimit:"Ce numéro a déjà 2 réservations non confirmées aujourd'hui. Confirmez-en une avec son code ou appelez la clinique au 416 555 0100.",
    verify:'Vérifiez votre téléphone',step4:'Étape 4 sur 4 · Code',otpTo:'Nous avons envoyé un code à 6 chiffres au {phone}. Il expire dans 10 minutes.',confirmBooking:'Confirmer la réservation',resend:'Renvoyer le code',summary:'Résumé',errDigits:'Entrez les 6 chiffres du code.',errCode:'Ce code ne correspond pas. Vérifiez le texto et réessayez.',newCode:'Nouveau code envoyé',
    booked:'Votre rendez-vous est confirmé',bookedFor:'Le rendez-vous de {name} est confirmé',bookedSub:"Confirmation envoyée par texto et par courriel. Le lien qu'elle contient vous connecte : aucun mot de passe à retenir.",next:'Prochaines étapes',calendar:'Ajouter à mon calendrier',calendarAdded:'Ajouté à votre calendrier. Les changements et annulations le mettent à jour automatiquement.',done:'Terminé',
    forWho:'Pour {name}',dayShort:'mar. 29 sept.',timeNotChosen:'heure non choisie',now:'Maintenant',today:"Aujourd'hui",fill:'Remplir',form:'Formulaire du motif de la visite',formSub:"2 minutes · aide l'accueil à se préparer",
    noReminder:'Aucun rappel nécessaire',noReminderSub:"Votre rendez-vous est aujourd'hui. Nous vous avertirons à l'ouverture de l'enregistrement.",checkin:'Enregistrez-vous depuis votre téléphone',checkinSub:'Ouvert 1 heure avant, à moins de 200 m de la clinique',
    k_welcome:'Bienvenue à la {name}',k_intro:"Enregistrez-vous pour votre rendez-vous d'aujourd'hui. Entrez les 4 derniers chiffres de votre numéro de téléphone.",k_clear:'Effacer',k_del:'Supprimer',k_err4:'Entrez les 4 derniers chiffres de votre numéro de téléphone.',k_none:"Nous n'avons trouvé aucun rendez-vous aujourd'hui pour ce numéro. Veuillez vous adresser à l'accueil.",
    k_isYou:'Est-ce vous?',k_with:'{time} avec {who}',k_notMe:"Ce n'est pas moi",k_privacy:'Seules les initiales sont affichées, par souci de confidentialité.',k_done:'Votre arrivée est enregistrée',k_ticket:"Votre numéro. Veuillez vous asseoir; l'écran appellera ce numéro.",k_finish:'Terminé'},
};
function tl(lang,k,v={}){let s=(PL[lang]||PL.en)[k]??PL.en[k]??k;for(const x in v)s=s.replace('{'+x+'}',v[x]);return s}
const tr=(k,v)=>tl(state.pLang,k,v);
const fmtT=(t,lang=state.pLang)=>lang==='fr'?frTime(t):ampm(t);
const svcLabel=s=>state.pLang==='fr'&&s.fr?s.fr:s.name;
const roleLabel=c=>state.pLang==='fr'&&c.roleFr?c.roleFr:c.role;
const BOOK_SCREENS=['book','book2','book3','otp','confirmed'];
function langSwitch(cur,fn){return [['en','English'],['fr','Français']].map(([k,l])=>`<button lang="${k}" aria-pressed="${cur===k}" onclick="${fn}('${k}')">${l}</button>`).join('')}
function setPatientLang(l){state.pLang=l;renderPatient()}

function startBooking(){const m=me();state.booking={mode:'new',service:state.services.find(s=>s.online).name,clin:'osei',time:null,who:'me'};releaseLocks('patient');showErr('p-slot-err');pgo('book')}
function startReschedule(){const m=me();state.booking={mode:'resched',target:m.id,service:m.svcFull||'Physiotherapy · follow-up',clin:m.clin,time:null,who:'me'};releaseLocks('patient');showErr('p-slot-err');pgo('book2')}
function pickService(name){state.booking.service=name;const s=svcByName(name);if(!s.clins.includes(state.booking.clin))state.booking.clin=s.clins[0];state.booking.time=null;releaseLocks('patient');renderPatient()}
function pickClin(id){state.booking.clin=id;state.booking.time=null;releaseLocks('patient');showErr('p-slot-err');renderPatient()}
function candidateClins(){const s=svcByName(state.booking.service);return state.booking.clin==='any'?s.clins:[state.booking.clin]}
function patientSlot(t){
  const ignore=state.booking.mode==='resched'?state.booking.target:undefined;
  const sts=candidateClins().map(c=>[c,slotState(c,t,'patient',ignore)]);
  const ok=sts.find(([,s])=>s==='free'||s==='freed');
  return ok?{clin:ok[0],state:ok[1]}:{clin:null,state:sts.some(([,s])=>s==='held'||s==='offered')?'held':sts.every(([,s])=>s==='blocked')?'blocked':'taken'};
}
function selectSlot(t){
  const s=patientSlot(t);if(!s.clin)return;
  if(!acquireLock(s.clin,t,'patient',300)){showErr('p-slot-err',tr('slotBusy'));return}
  state.booking.time=t;state.booking.lockedClin=s.clin;showErr('p-slot-err');renderAll();
}
// the patient's hold must still be live on every later step; if it ran out, they choose again
const holdOk=()=>{const b=state.booking;return !!(b.time&&lockAt(b.lockedClin,b.time))};
function backToTimes(){state.booking.time=null;pgo('book2');showErr('p-slot-err',tr('holdExpired'))}
function book2Next(){
  const b=state.booking;
  if(!holdOk()){if(b.time)return backToTimes();showErr('p-slot-err',tr('pickTime'));return}
  if(b.mode==='resched')return confirmReschedule();
  pgo('book3');
}
function sendCode(){
  if(!holdOk())return backToTimes();
  const name=$('#p-name').value.trim(),ph=digits($('#p-phone').value);
  if(!name)return showErr('p-details-err',tr('errName'));
  if(ph.length<10)return showErr('p-details-err',tr('errPhone'));
  if(!$('#p-c2').checked)return showErr('p-details-err',tr('errPolicy'));
  const pend=state.otp.pending[ph]||0;
  if(pend>=2){logAudit('Guest '+ph.slice(-4),'booking.rate_limited','PHONE …'+ph.slice(-4),`Blocked: ${pend} unconfirmed bookings today (limit 2)`);return showErr('p-details-err',tr('errLimit'))}
  showErr('p-details-err');state.otp.pending[ph]=pend+1;state.otp.code=newCode();state.otp.phone=ph;
  $('#p-otp-to').textContent=tr('otpTo',{phone:$('#p-phone').value.trim()});
  $$('#p-otp input').forEach(i=>i.value='');showErr('p-otp-err');
  pgo('otp');smsBanner(`ClinicFlow: ${state.otp.code} is your Maple Grove Clinic code. Don't share it.`);
  setTimeout(()=>$('#p-otp input')?.focus(),50);
}
function resendCode(){state.otp.code=newCode();smsBanner(`ClinicFlow: ${state.otp.code} is your new Maple Grove Clinic code.`);toast('p',tr('newCode'))}
function fillCode(){if(!state.otp.code)return;[...state.otp.code].forEach((d,i)=>$$('#p-otp input')[i].value=d)}
function confirmBooking(){
  const code=$$('#p-otp input').map(i=>i.value).join('');
  if(code.length<6)return showErr('p-otp-err',tr('errDigits'));
  if(code!==state.otp.code)return showErr('p-otp-err',tr('errCode'));
  if(!holdOk())return backToTimes();
  const b=state.booking,who=whoName(),svc=svcByName(b.service);
  // the phone code is the confirmation: a verified booking doesn't need a second "please confirm"
  const entry={name:who,clin:b.lockedClin,time:b.time,svc:svc.short,svcFull:svc.name,status:'confirmed',forms:false,phone:state.otp.phone.slice(-4),mine:true,guardian:who!=='Priya Raman'};
  if(!commitBooking(entry,'patient')){b.time=null;pgo('book2');showErr('p-slot-err',tr('slotGone'));return}
  state.otp.pending[state.otp.phone]=Math.max(0,(state.otp.pending[state.otp.phone]||1)-1);state.otp.code=null;
  if($('#p-c1').checked&&!state.consent.sms){state.consent={sms:true,at:'Sep 29, 2026'};logAudit(PATIENT,'consent.sms.granted','PAT-0142','Text reminders consent captured at booking')}
  state.pSigned=true;
  logAudit(entry.guardian?'Priya Raman (guardian)':PATIENT,'appointment.create','APT-'+(20900+entry.id),`${svc.short} · ${clinById(entry.clin).short} · Tue ${ampm(entry.time)} · phone verified · guest link`);
  notifyPatient(`Booked${entry.guardian?' for '+who.split(' ')[0]:''}: ${svc.short}, Tue Sep 29, ${ampm(entry.time)} with ${clinById(entry.clin).short}.`,'text and email','good');
  alertStaff(`New online booking: ${who}, ${ampm(entry.time)} with ${clinById(entry.clin).short} (${entry.guardian?'booked by guardian Priya Raman':'guest'}, phone verified).`,'info');
  deliver(who,'Booking confirmation','Push, then text, then email','Delivered');
  state.lastBooked=entry.id;pgo('confirmed');
}
function confirmReschedule(){
  const b=state.booking,q=state.queue.find(x=>x.id===b.target),old={clin:q.clin,time:q.time};
  if(slotState(b.lockedClin,b.time,'patient',q.id)!=='free'&&slotState(b.lockedClin,b.time,'patient',q.id)!=='freed'){showErr('p-slot-err','That time was just taken. Pick another.');return}
  const f=freedAt(b.lockedClin,b.time);if(f){f.status='filled';f.filledBy=q.name;state.recovery.refilled++}
  q.clin=b.lockedClin;q.time=b.time;delete state.locks[lockKey(q.clin,q.time)];
  logAudit(PATIENT,'appointment.reschedule','APT-'+(20900+q.id),`${clinById(old.clin).short} ${ampm(old.time)} → ${clinById(q.clin).short} ${ampm(q.time)}`);
  notifyPatient(`Moved: your visit is now Tue Sep 29, ${ampm(q.time)} with ${clinById(q.clin).short}.`,'push and text','good');
  freeSlot(old.clin,old.time,`${q.name} rescheduled`);
  toast('p',`Moved to ${ampm(q.time)}`);touch();pgo('appt');
}
const hoursUntil=q=>(slotMin(q.time)-nowMin())/60;
// cancelling is the one patient action that can't be undone, so it asks first and names the policy
function askCancel(){
  const q=me();if(!q)return;const late=hoursUntil(q)<state.rules.cancelWindow,sh=$('#p-sheet');
  sh.innerHTML=`<div class="sheet" role="dialog" aria-modal="true" aria-labelledby="p-sheet-h"><h3 id="p-sheet-h">Cancel your ${ampm(q.time)} visit?</h3><p class="small">${esc(q.svcFull||q.svc)} with ${esc(clinById(q.clin).name)}, today${forLabel(q.name)}.</p>${late?`<div class="banner">Your visit is less than ${state.rules.cancelWindow} hours away, so the clinic may record a late cancellation.</div>`:''}<p class="small muted">Your time goes to the next person on the waitlist. You can book again any time.</p><button class="btn primary block" id="p-sheet-keep" onclick="closeSheet()">Keep my visit</button><button class="btn danger block" onclick="closeSheet(true);cancelAppt()">Cancel visit</button></div>`;
  sh.hidden=false;$('#p-sheet-keep').focus();
}
function closeSheet(done){$('#p-sheet').hidden=true;if(!done)$('#p-appt-actions .danger')?.focus()}
function cancelAppt(){
  const q=me();if(!q)return;const late=hoursUntil(q)<state.rules.cancelWindow;q.status='cancelled';releaseLocks('patient');
  logAudit(PATIENT,'appointment.cancel','APT-'+(20900+q.id),`${q.svc} · ${ampm(q.time)} · cancelled in app${late?` · inside the ${state.rules.cancelWindow} h window · recorded as late cancellation`:''}`);
  notifyPatient(`Your ${ampm(q.time)} visit is cancelled. The slot was offered to the waitlist.`,'push','mute');
  freeSlot(q.clin,q.time,`${q.name} cancelled`);
  toast('p','Visit cancelled. Your time is offered to the waitlist.');pgo('home');
}
function confirmVisit(){const q=me();if(!q||q.status!=='booked')return;q.status='confirmed';logAudit(PATIENT,'appointment.confirm','APT-'+(20900+q.id),'One-tap confirm from the 24 h reminder');alertStaff(`${q.name} confirmed ${ampm(q.time)} from the reminder.`,'good');toast('p','Thanks, your visit is confirmed');renderAll()}
function toggleChip(kind,val){const a=state.wlPrefs[kind];const i=a.indexOf(val);i<0?a.push(val):a.splice(i,1);renderPatient()}
function joinWaitlist(){
  const p=state.wlPrefs;if(!p.days.length||!p.times.length){toast('p','Pick at least one day and one time');return}
  let w=myWl();if(!w){w={id:'w'+(state.nextId++),name:'Priya Raman',svc:'Physio',mine:true,joined:'Sep 29',priority:false};state.waitlist.push(w)}
  Object.assign(w,{clin:p.clin,days:[...p.days],times:[...p.times],status:'waiting'});
  logAudit(PATIENT,'waitlist.join','WL-'+w.id,`Physio · ${p.days.join('/')} · ${p.times.join(', ')} · ${p.clin==='any'?'any clinician':'Dr. Osei'}`);
  alertStaff('Priya Raman joined the waitlist for a different time.','info');
  toast('p',"You're on the waitlist. We'll text you first.");pgo('home');
  // the current holder's 15-minute hold runs out, so the open offer moves down the list
  setTimeout(()=>{const f=state.freed.find(f=>f.status==='offered');if(f){f.offers.filter(o=>o.status==='holding').forEach(o=>{o.status='expired';const ww=state.waitlist.find(x=>x.id===o.wl);if(ww)ww.status='waiting'});alertStaff(`${f.offers.at(-1).name}'s hold on ${ampm(f.time)} expired. Moving to the next match.`,'mute');cascade(f)}if(state.pendingOffer&&cur.surface==='patient')pgo('offer');else renderAll()},1500);
}
function acceptOffer(){
  const f=state.freed.find(x=>x.id===state.pendingOffer);const q=me();if(!f||!q)return pgo('home');
  const old={clin:q.clin,time:q.time},o=f.offers.find(o=>o.status==='holding');if(o)o.status='accepted';
  f.status='filled';f.filledBy=q.name;state.recovery.refilled++;q.clin=f.clin;q.time=f.time;
  const w=myWl();if(w)w.status='booked';state.pendingOffer=null;
  logAudit(PATIENT,'waitlist.offer.accepted','SLOT '+f.clin+' '+f.time,`Moved from ${ampm(old.time)} · refilled ${fmtSecs(Math.round((Date.now()-f.freedAt)/1000))} after it opened`);
  notifyPatient(`Moved: your visit is now Tue Sep 29, ${ampm(q.time)} with ${clinById(q.clin).short}.`,'push and text','good');
  alertStaff(`Waitlist offer accepted: Priya Raman took ${ampm(f.time)} with ${clinById(f.clin).short}.`,'good');
  freeSlot(old.clin,old.time,'Priya Raman moved to a waitlist slot');
  toast('p','The slot is yours');pgo('home');
}
function declineOffer(){const f=state.freed.find(x=>x.id===state.pendingOffer);if(f){const o=f.offers.find(o=>o.status==='holding');if(o)o.status='declined';const w=myWl();if(w)w.status='passed';logAudit(PATIENT,'waitlist.offer.declined','SLOT '+f.clin+' '+f.time,'Kept current time');setTimeout(()=>{cascade(f);renderAll()},800)}state.pendingOffer=null;toast('p','Kept your current time');pgo('home')}
function submitIntake(){const q=me();if(!q)return;q.forms=true;state.intake[q.id]={type:$('#p-r1').value,note:$('#p-r3').value.trim()};logAudit(PATIENT,'intake.submit','APT-'+(20900+q.id),'Reason-for-visit form (operational fields only)');alertStaff(`${q.name} completed the reason-for-visit form.`,'good');toast('p','Form received. The front desk can see it.');pgo('home')}
function checkInEntry(q,via,actor){
  if(!q.ticket)q.ticket='A-'+(state.nextTicket++);q.status='checked';q.checkedAt=clock12();
  logAudit(actor,'appointment.checkin','APT-'+(20900+q.id),`Checked in via ${via} · ticket ${q.ticket}`);
  alertStaff(`${q.name} checked in (${via}). Ticket ${q.ticket}.`,'good');touch();
}
function checkIn(){const q=me();if(!q)return;checkInEntry(q,'phone, 140 m from the clinic',PATIENT);renderAll()}
function addFamily(){const name=$('#p-fam-name').value.trim();if(!name){toast('p','Enter their full name');$('#p-fam-name').focus();return}if(!$('#p-fam-ok').checked){toast('p','Confirm you can book for them');return}const f={id:'f'+Date.now(),name,rel:$('#p-fam-rel').value,dob:$('#p-fam-dob').value};state.family.push(f);state.booking.who=f.id;$('#p-fam-name').value='';$('#p-fam-dob').value='';$('#p-fam-ok').checked=false;logAudit(PATIENT,'family.add','PAT-0142',`Added ${f.rel.toLowerCase()} · guardian consent confirmed`);toast('p',`${name.split(' ')[0]} added`);pgo(state.famFrom==='book'?'book':'family')}
function payBalance(){const owing=state.history.reduce((t,v)=>t+v.owing,0);state.history.forEach(v=>v.owing=0);logAudit(PATIENT,'payment.received','PAT-0142',`$${owing.toFixed(2)} paid online`);alertStaff(`Priya Raman paid $${owing.toFixed(2)} online. Receipt emailed.`,'good');toast('p',`Paid $${owing.toFixed(2)}. Receipt emailed.`);renderPatient()}
function toggleSmsConsent(){state.consent=state.consent.sms?{sms:false,at:'Sep 29, 2026'}:{sms:true,at:'Sep 29, 2026'};logAudit(PATIENT,state.consent.sms?'consent.sms.granted':'consent.sms.withdrawn','PAT-0142','Changed in Profile');toast('p',state.consent.sms?'Text reminders on':'Text reminders off. We will use push and email.');renderPatient()}
function toggleLargeText(){state.largeText=!state.largeText;$('#p-phone-frame').classList.toggle('large',state.largeText);renderPatient()}
function patientSignOut(){state.pSigned=false;logAudit(PATIENT,'auth.signout','PAT-0142','Patient app');$('#p-si-code-wrap').hidden=true;$('#p-si-btn').textContent='Send me a code';showErr('p-si-err');pgo('signin')}
function patientSendCode(){
  const wrap=$('#p-si-code-wrap');
  if(wrap.hidden){if(digits($('#p-si-phone').value).length<10&&!$('#p-si-phone').value.includes('@'))return showErr('p-si-err','Enter the mobile number or email you booked with.');state.pCode=newCode();wrap.hidden=false;$('#p-si-btn').textContent='Sign in';showErr('p-si-err');smsBanner(`ClinicFlow: ${state.pCode} is your sign-in code.`);return}
  if($('#p-si-code').value.trim()!==state.pCode)return showErr('p-si-err',"That code doesn't match. Check the message and try again.");
  patientSignedIn('one-time code');
}
function patientFaceId(){toast('p','Face ID recognised');setTimeout(()=>patientSignedIn('Face ID'),500)}
function patientSignedIn(how){state.pSigned=true;$('#p-si-code').value='';logAudit(PATIENT,'auth.signin','PAT-0142','Patient app · '+how);pgo('home')}

function lockLeft(){const b=state.booking,lk=b.time&&lockAt(b.lockedClin,b.time);if(!lk)return null;const s=Math.max(0,Math.round((lk.until-Date.now())/1000));return `${Math.floor(s/60)}:${String(s%60).padStart(2,'0')}`}
// countdowns change text only, never markup, so typing and focus are never disturbed
function updateLocks(){
  const b=state.booking,left=lockLeft();
  $$('.p-lockbar').forEach(el=>{el.hidden=!left;if(!left)return;const sp=el.querySelector('span');const txt=tr('held',{time:fmtT(b.time),who:clinById(b.lockedClin).short,left});if(sp)sp.textContent=txt;else el.innerHTML=`${ic('lock')} <span>${esc(txt)}</span>`});
  const m=state.manual,ml=$('#w-mb-lock');if(m&&ml){const lk=m.time&&lockAt(m.clin,m.time);ml.hidden=!lk;if(lk)ml.lastChild.textContent=` ${ampm(m.time)} is held for you for ${Math.max(0,Math.round((lk.until-Date.now())/1000))} s. Nobody else can book it meanwhile.`}
}
function bookingSummary(svc,who,clin,time){return `<b>${esc(svcLabel(svc))}</b><br>${tr('forWho',{name:esc(who)})}<br>${esc(clinById(clin).name)}<br>${tr('dayShort')} · ${time?fmtT(time):tr('timeNotChosen')}<br>Maple Grove Clinic, 214 Elm Ave`}

function renderPatient(){
  const q=me(),b=state.booking;
  // booking link and its steps follow the patient's language
  BOOK_SCREENS.forEach(s=>{const el=$(`#p-screens [data-s="${s}"]`);if(el)el.lang=state.pLang});
  $$('#p-screens [data-t]').forEach(el=>{el.textContent=tr(el.dataset.t)});
  $('#p-lang').innerHTML=langSwitch(state.pLang,'setPatientLang');$('#p-lang2').innerHTML=langSwitch(state.pLang,'setPatientLang');
  // home
  const reasonDone=q&&q.forms;
  $('#p-todo-count').textContent=reasonDone?'0 left':'1 left';$('#p-todo-count').className=`pill ${reasonDone?'good':'warn'}`;
  $('#p-reason-todo').innerHTML=reasonDone?'<span class="pill good">Done</span><div class="grow"><div class="t">Reason for visit</div><div class="s">Submitted</div></div>':'<span class="pill warn">Open</span><div class="grow"><div class="t">Reason for visit</div><div class="s">2 min · needed before your visit</div></div><button class="btn sm" onclick="pgo(\'intake\')">Fill in</button>';
  $('#p-consent-line').textContent=state.consent.sms?`Text reminders on since ${state.consent.at}`:'Text reminders off · push and email only';
  $('#p-notice').textContent=state.notice;
  $('#p-near-count').textContent=`${state.directory.filter(c=>c.accepting&&!c.self).length} nearby accepting patients`;
  const h=$('#p-hero');
  if(!q||q.status==='cancelled'||q.status==='noshow')h.innerHTML=`<p class="eyebrow">No upcoming visit</p><h3>Book when you're ready</h3><div class="row"><button class="btn" onclick="startBooking()">Book a visit</button></div>`;
  else if(q.status==='checked'||q.status==='waiting'){const ahead=queueAhead(q);h.innerHTML=`<p class="eyebrow">${q.status==='checked'?'The front desk is adding you to the queue':ahead?`${ahead} ${ahead===1?'person':'people'} ahead of you · about ${Math.max(3,ahead*5+3)} min`:"You're next"}</p><h3>Checked in · ticket ${q.ticket}</h3><p style="margin-bottom:10px;opacity:.9">We'll send a push when it's your turn.</p><div class="row"><button class="btn" onclick="pgo('checkin')">See your place</button></div>`}
  else if(q.status==='invisit')h.innerHTML=`<p class="eyebrow">Now</p><h3>${clinById(q.clin).short} is ready for you</h3><p style="opacity:.9">Room 2, down the hall on the left.</p>`;
  else if(q.status==='done')h.innerHTML=`<p class="eyebrow">Visit complete</p><h3>Thanks, Priya</h3><p style="margin-bottom:10px;opacity:.9">Book your next follow-up while it's fresh.</p><div class="row"><button class="btn" onclick="startBooking()">Book follow-up</button></div>`;
  // the action that matters most comes first and is the filled one: confirm, then "I'm here"
  else h.innerHTML=`<p class="eyebrow">Next visit · today, Tue Sep 29 · ${q.status==='confirmed'?'confirmed':q.status==='late'?'you are running late':'please confirm'}</p><h3>${ampm(q.time)} · ${esc(q.svc)}</h3><p style="margin-bottom:10px;opacity:.9">${clinById(q.clin).name} · Maple Grove Clinic${forLabel(q.name)}</p><div class="row">${q.status==='booked'?`<button class="btn" onclick="confirmVisit()">Confirm I'm coming</button>`:`<button class="btn" onclick="pgo('checkin')">I'm here</button>`}<button class="btn" onclick="pgo('appt')">Manage visit</button></div>`;
  // directory
  const term=($('#p-find')?.value||'').toLowerCase().trim();
  const list=state.directory.filter(c=>(!term||(c.name+' '+c.services).toLowerCase().includes(term.replace(/therapy$/,'')))&&(state.findFilter==='all'||(state.findFilter==='accepting'?c.accepting:c.today)));
  $$('#p-find-filter button').forEach(x=>x.setAttribute('aria-pressed',x.getAttribute('onclick').includes(`'${state.findFilter}'`)));
  $('#p-clinics').innerHTML=list.length?list.map(c=>`<div class="item"><div class="avatar">${c.ini}</div><div class="grow"><div class="t">${c.name}</div><div class="s">${c.dist} km · ${c.services} · ${c.next}</div></div>${c.self?'<button class="btn sm primary" onclick="startBooking()">Book</button>':c.accepting?`<button class="btn sm" onclick="toast('p','Opens ${c.name}&#39;s booking page')">Book</button>`:`<button class="btn sm" onclick="toast('p','Added to ${c.name}&#39;s waitlist')">Join list</button>`}</div>`).join(''):'<div class="item"><div class="s">No clinics match. Try "physio" or switch the filter to All.</div></div>';
  // booking
  $('#p-who').innerHTML=[['me',tr('me')],...state.family.map(f=>[f.id,f.name.split(' ')[0]])].map(([id,l])=>`<button aria-pressed="${b.who===id}" onclick="state.booking.who='${id}';renderPatient()">${esc(l)}</button>`).join('')+`<button aria-pressed="false" onclick="state.famFrom='book';pgo('family')">${tr('addSomeone')}</button>`;
  $('#p-services').innerHTML=state.services.filter(s=>s.online).map(s=>`<button class="choice" aria-pressed="${b.service===s.name}" onclick="pickService(this.dataset.n)" data-n="${esc(s.name)}"><div class="grow"><div class="t">${esc(svcLabel(s))}</div><div class="s small muted">${s.dur} min · ${state.pLang==='fr'&&s.whoFr?s.whoFr:s.who}</div></div></button>`).join('');
  const svc=svcByName(b.service),res=b.mode==='resched';
  $('#p-book2-title').textContent=res?tr('book2Resched'):tr('book2Title');$('#p-book2-steps').hidden=res;$('#p-clin-label').textContent=res?tr('clinician'):tr('step2');
  $('#p-book2-next').textContent=res?tr('move'):tr('continue');
  const clinOpts=svc.clins.map(id=>clinById(id)).concat(svc.clins.length>1?[{id:'any',name:tr('anyClin'),role:tr('anyRole')}]:[]);
  $('#p-clin').innerHTML=clinOpts.map(c=>`<button class="choice" aria-pressed="${b.clin===c.id}" onclick="pickClin('${c.id}')"><div class="avatar" aria-hidden="true">${c.id==='any'?'·':initials(c.name)}</div><div class="grow"><div class="t">${esc(c.name)}</div><div class="small muted">${esc(c.id==='any'?c.role:roleLabel(c))}${c.id!=='any'&&capacity(c.id)===0?' · '+tr('notTue'):''}</div></div></button>`).join('');
  const lab={taken:tr('taken'),blocked:tr('unavailable'),held:tr('heldOther')};
  $('#p-slots').innerHTML=TIMES.map(t=>{const s=patientSlot(t),sel=b.time===t;const dis=!s.clin&&!sel;return `<button aria-pressed="${sel}" class="${s.state==='freed'?'freed':''}" ${dis?'disabled':''} aria-label="${fmtT(t)}${dis?', '+lab[s.state]:''}" onclick="selectSlot('${t}')">${fmtT(t)}</button>`}).join('');
  $('#p-slot-note').textContent=capacity(b.clin==='any'?svc.clins[0]:b.clin)===0?tr('slotNoteOff'):tr('slotNote');
  const sum=bookingSummary(svc,whoName(),b.lockedClin&&b.time?b.lockedClin:b.clin,b.time);
  $('#p-summary').innerHTML=sum;$('#p-summary3').innerHTML=sum;
  updateLocks();
  const lb=state.queue.find(x=>x.id===state.lastBooked);
  $('#p-summary2').innerHTML=lb?bookingSummary(svcByName(lb.svcFull),lb.name,lb.clin,lb.time):'';
  $('#p-confirmed-title').textContent=lb&&lb.guardian?tr('bookedFor',{name:lb.name.split(' ')[0]}):tr('booked');
  // every prototype booking is for today, so the timeline is the same-day one: no 48 h / 24 h reminders to promise
  $('#p-next').innerHTML=`${lb&&!lb.forms?`<div class="item"><span class="pill warn">${tr('now')}</span><div class="grow"><div class="t">${tr('form')}</div><div class="s">${tr('formSub')}</div></div><button class="btn sm" onclick="pgo('intake')">${tr('fill')}</button></div>`:''}<div class="item"><span class="pill mute">${tr('today')}</span><div class="grow"><div class="t">${tr('noReminder')}</div><div class="s">${tr('noReminderSub')}</div></div></div><div class="item"><span class="pill mute">${tr('today')}</span><div class="grow"><div class="t">${tr('checkin')}</div><div class="s">${tr('checkinSub')}</div></div></div>`;
  // your visit
  if(q){
    $('#p-apptcard').innerHTML=`<div class="row between"><p class="eyebrow">Today, Tue Sep 29</p>${pill(q.status)}</div><h3 style="font-size:20px;margin:4px 0">${ampm(q.time)} · ${esc(q.svc)}</h3><p class="small muted">${esc(q.svcFull||q.svc)} · ${clinById(q.clin).name} · Maple Grove Clinic, 214 Elm Ave${forLabel(q.name)}</p><div class="row" style="margin-top:10px;gap:var(--space-sm)"><span class="pill ${q.forms?'good':'warn'}">Forms ${q.forms?'done':'1 open'}</span><span class="pill mute">Ref APT-${20900+q.id}</span></div>`;
    const stages=[['booked','Booked'],['confirmed','Confirmed'],['checked','Checked in'],['waiting','Waiting'],['done','Complete']];
    const pos={booked:0,late:0,confirmed:1,checked:2,waiting:3,invisit:3,done:5}[q.status];
    $('#p-tracker').innerHTML=pos===undefined?`<li class="now">This visit was ${q.status==='noshow'?'missed':'cancelled'}.</li>`:stages.map(([k,l],i)=>`<li class="${i<pos?'done':i===pos?'now':''}"${i===pos?' aria-current="step"':''}><i>${i<pos?ic('check'):i+1}</i><span>${l}${k==='waiting'&&q.status==='invisit'?' · now in your visit':''}${i===pos&&k==='booked'?' · please confirm':''}</span></li>`).join('');
    const live=!['cancelled','noshow','done'].includes(q.status),early=['booked','confirmed','late'].includes(q.status);
    $('#p-appt-actions').innerHTML=!live?'<button class="btn primary block" onclick="startBooking()">Book again</button>':(q.status==='booked'?'<button class="btn primary block" onclick="confirmVisit()">Confirm I\'m coming</button>':early?'<button class="btn primary block" onclick="pgo(\'checkin\')">I\'m here</button>':'')+(early?'<button class="btn block" onclick="startReschedule()">Change the time</button><button class="btn block" onclick="pgo(\'waitlist\')">Get offered an earlier time</button><button class="btn danger block" onclick="askCancel()">Cancel visit</button>':'');
    $('#p-policy').textContent=`Free cancellation until ${state.rules.cancelWindow} hours before your visit. After that the clinic may record a late cancellation.`;
  }
  // waitlist preferences
  const p=state.wlPrefs,chip=(kind,v,l)=>`<button aria-pressed="${p[kind].includes(v)}" onclick="toggleChip('${kind}','${v}')">${l}</button>`;
  $('#p-wl-prefs').innerHTML=`<p class="eyebrow">Days</p><div class="slots">${['Mon','Tue','Wed','Thu','Fri','Sat'].map(d=>chip('days',d,d)).join('')}</div><p class="eyebrow">Times</p><div class="slots">${chip('times','morning','Morning')}${chip('times','afternoon','Afternoon')}${chip('times','after4','After 4 pm')}</div><p class="eyebrow">Clinician</p><div class="seg"><button aria-pressed="${p.clin==='any'}" onclick="state.wlPrefs.clin='any';renderPatient()">Any</button><button aria-pressed="${p.clin==='osei'}" onclick="state.wlPrefs.clin='osei';renderPatient()">Dr. Osei only</button></div>`;
  const of=state.freed.find(x=>x.id===state.pendingOffer);
  $('#p-offer-title').textContent=of&&q&&slotMin(of.time)<slotMin(q.time)?'An earlier time opened':'A time opened up';
  $('#p-offer-hero').innerHTML=of?`<p class="eyebrow">Waitlist offer · held for you for ${state.rules.hold} minutes</p><h3>Today, ${ampm(of.time)}</h3><p style="opacity:.9">Physiotherapy · ${clinById(of.clin).name} · Maple Grove Clinic${q?` · instead of ${ampm(q.time)}`:''}</p>`:'<h3>This offer has ended</h3>';
  // check-in
  const c=$('#p-checkin');
  if(!q||!['booked','confirmed','late','checked','waiting','invisit','done'].includes(q.status))c.innerHTML='<div class="card"><p class="small muted">No visit to check in for today.</p></div>';
  else if(['booked','confirmed','late'].includes(q.status))c.innerHTML=`<div class="card stack"><p class="eyebrow">Today · ${ampm(q.time)} · ${clinById(q.clin).short}</p><p>You're 140 m from Maple Grove Clinic. Check-in is open.</p>${q.forms?'':'<div class="banner">One form is still open. You can check in now and finish it while you wait.</div>'}<button class="btn primary block" onclick="checkIn()">I'm here</button><p class="small muted" style="text-align:center">No phone signal? On the front-desk tablet, enter the last 4 digits of your phone: <b class="num">${q.phone||'0142'}</b></p></div>`;
  else if(q.status==='checked'||q.status==='waiting'){const ahead=queueAhead(q);c.innerHTML=`<div class="card ticket-card" aria-live="polite"><h3>You're checked in</h3><b class="ticket" aria-label="Ticket ${q.ticket}">${q.ticket}</b><p class="small muted">Your ticket. The waiting-room screen calls this number, never your name.</p><p><b>${q.status==='checked'?'The front desk is adding you to the queue':ahead?`${ahead} ${ahead===1?'person':'people'} ahead of you`:"You're next"}</b>${q.status==='checked'?'':` · about ${Math.max(3,ahead*5+3)} min`}</p><p class="small muted">Feel free to step out; we'll send a push when you're next.</p></div><div class="card list"><div class="item"><span class="pill good">Checked in</span><div class="grow"><div class="t">${q.checkedAt||''}</div><div class="s">Front desk notified</div></div></div>${q.forms?'':'<div class="item"><span class="pill warn">Open</span><div class="grow"><div class="t">Reason for visit</div><div class="s">Finish while you wait</div></div><button class="btn sm" onclick="pgo(\'intake\')">Fill in</button></div>'}<div class="item"><span class="pill mute">Now</span><div class="grow"><div class="t">Serving ${nowServing()||'no one yet'}</div><div class="s">The waiting-room board shows ticket numbers only</div></div></div></div>`}
  else if(q.status==='invisit')c.innerHTML=`<div class="hero info"><p class="eyebrow">Now</p><h3>Please go to Room 2</h3><p style="opacity:.9">${clinById(q.clin).name} · down the hall on the left</p></div>`;
  else c.innerHTML=`<div class="card" style="text-align:center"><div class="avatar big-check">${ic('check')}</div><h3>Visit complete</h3><p class="small muted">Book your next follow-up from Home.</p></div>`;
  // family, history, notifications, profile
  $('#p-family').innerHTML=state.family.length?state.family.map(f=>`<div class="item"><div class="avatar">${initials(f.name)}</div><div class="grow"><div class="t">${esc(f.name)}</div><div class="s">${esc(f.rel)} · born ${niceDate(f.dob)}</div></div><button class="btn sm" onclick="startBooking();state.booking.who='${f.id}';renderPatient()">Book</button></div>`).join(''):'<div class="item"><div class="s">No one added yet.</div></div>';
  const owing=state.history.reduce((t,v)=>t+v.owing,0);
  $('#p-balance').innerHTML=`<div class="row between"><div><p class="eyebrow">Balance owing</p><b class="figure">$${owing.toFixed(2)}</b></div>${owing?'<button class="btn sm primary" onclick="payBalance()">Pay now</button>':'<span class="pill good">All paid</span>'}</div>`;
  $('#p-history').innerHTML=state.history.map(v=>`<div class="item"><span class="pill ${v.owing?'warn':'good'}">${v.owing?'$'+v.owing+' owing':'Paid'}</span><div class="grow"><div class="t">${v.svc}</div><div class="s">${v.date} · ${v.clin} · ${v.clinic}${forLabel(v.who)}</div></div><button class="btn sm" onclick="toast('p','Receipt for ${v.date} emailed')">Receipt</button></div>`).join('');
  $('#p-notifs').innerHTML=state.pNotifs.map(n=>{let act='';if(n.act==='confirm'&&q&&q.status==='booked')act='<div class="actions"><button class="btn sm primary" onclick="confirmVisit()">Confirm</button><button class="btn sm" onclick="startReschedule()">Change the time</button></div>';else if(n.act==='intake'&&q&&!q.forms)act='<div class="actions"><button class="btn sm" onclick="pgo(\'intake\')">Fill in the form</button></div>';else if(n.act==='offer'&&state.pendingOffer)act='<div class="actions"><button class="btn sm primary" onclick="pgo(\'offer\')">See offer</button></div>';return `<div class="item"><div class="grow"><div class="t">${esc(n.t)}</div><div class="s"><span class="kind ${n.k}">${PKIND[n.k]||'Notice'}</span> · ${esc(n.s)}</div>${act}</div></div>`}).join('');
  $('#p-sms-consent').textContent=state.consent.sms?`On · consent given ${state.consent.at}`:`Off · withdrawn ${state.consent.at}`;
  $('#p-sms-toggle').textContent=state.consent.sms?'Turn off':'Turn on';
  $('#p-large-toggle').textContent=state.largeText?'Turn off':'Turn on';
}
function queueAhead(q){return state.queue.filter(x=>x.status==='waiting'&&x.clin===q.clin&&x!==q&&tnum(x.ticket)<tnum(q.ticket)).length}
function nowServing(){const v=state.queue.filter(q=>q.status==='invisit').map(q=>q.ticket).filter(Boolean);return v.join(', ')}

// ---------- staff app ----------
function staffTabs(){const u=staffUser();if(!u)return['login'];return {admin:['queue','schedule','waitlist','alerts','me'],frontdesk:['queue','schedule','waitlist','alerts','me'],clinician:['queue','schedule','alerts','me'],support:['queue','alerts','me']}[u.role]}
function canAct(q,u=staffUser()){if(!u||u.role==='support')return false;return u.role!=='clinician'||q.clin===u.clin}
// one status change for the staff app and the website; every change can be undone for 6 seconds
function applyStatus(q,st,u,which){
  const prev=q.status,snap={status:q.status,ticket:q.ticket,checkedAt:q.checkedAt,waitStart:q.waitStart,since:q.since},nt=state.nextTicket,missedN=state.missed.length;
  if(st==='checked'){checkInEntry(q,which==='w'?'front desk (website)':'front desk',actorOf(u))}
  else{q.status=st;if(st==='waiting'){q.waitStart=Date.now();q.since=0}logAudit(actorOf(u),'appointment.status','APT-'+(20900+q.id),`${STATUS[prev][1]} → ${STATUS[st][1]}`)}
  if(q.mine&&st==='invisit')notifyPatient(`${clinById(q.clin).short} is ready. Please go to Room 2.`,'push','info');
  if(st==='noshow'){alertStaff(`${q.name} marked no-show for ${ampm(q.time)}. Listed in Missed visits.`,'crit');state.missed.unshift({id:Date.now(),date:'Today',time:ampm(q.time),name:q.name,clin:clinById(q.clin).short,svc:q.svc,reminder:prev==='booked'?'Delivered, no reply':'Confirmed by text',prior:0,status:'open'})}
  touch();
  const first=q.name.split(' ')[0];
  toast(which,{checked:`${first} checked in · ticket ${q.ticket}`,waiting:`${first} added to the queue`,invisit:`${first} called in`,done:`${first}'s visit complete`,noshow:`${first} marked no-show`}[st]||'Updated',()=>{
    Object.assign(q,snap);if(st==='checked')state.nextTicket=nt;state.missed.splice(0,state.missed.length-missedN);
    logAudit(actorOf(u),'appointment.status.undo','APT-'+(20900+q.id),`Undid ${STATUS[st][1]} · back to ${STATUS[prev][1]}`);
    touch();toast(which,`Undone. ${first} is ${STATUS[prev][1].toLowerCase()} again.`);renderAll();
  });
  renderAll();
}
function setStatus(id,st){const q=state.queue.find(x=>x.id===id),u=staffUser();if(!canAct(q,u))return toast('s','Your role can view this but not change it');applyStatus(q,st,u,'s')}
function webStatus(id,st){const q=state.queue.find(x=>x.id===id),u=webUser();if(!canAct(q,u))return toast('w','Your role can view this but not change it');applyStatus(q,st,u,'w')}
const lateBy=q=>Math.max(1,nowMin()-slotMin(q.time));
// the next thing to do for one patient. Only the single most urgent action on screen is filled.
function qActions(q,u,fn,primary){
  if(!canAct(q,u))return '';const b=(st,l,cls='')=>`<button class="btn sm ${cls}" onclick="${fn}(${q.id},'${st}')">${l}</button>`;
  if(q.status==='checked')return b('waiting','Add to queue',primary?'primary':'');
  if(q.status==='waiting')return b('invisit','Call in',primary?'primary':'');
  if(q.status==='invisit')return b('done','Complete');
  if(q.status==='late')return b('checked','Arrived')+`<button class="btn sm" onclick="textPatient(${q.id})">Text</button>`+b('noshow','No-show','danger');
  if(q.status==='booked'||q.status==='confirmed')return b('checked','Arrived')+(q.status==='booked'?`<button class="btn sm" onclick="remindPatient(${q.id})">Remind</button>`:'')+(q.forms?'':`<button class="btn sm" onclick="sendForm(${q.id})">Send form</button>`);
  return '';
}
function addWalkIn(){const u=staffUser();if(!u||!['admin','frontdesk'].includes(u.role))return;const n=++state.walkins;const t=TIMES.find(t=>tIdx(t)>=2&&!apptAt('walk',t))||'4:30';const q={id:state.nextId++,name:'Walk-in #'+n,clin:'walk',time:t,svc:'Walk-in',status:'waiting',forms:true,ticket:'A-'+(state.nextTicket++),waitStart:Date.now(),since:0};state.queue.push(q);logAudit(actorOf(u),'appointment.create','APT-'+(20900+q.id),`Walk-in #${n} · ticket ${q.ticket}`);alertStaff(`Walk-in #${n} added to the queue. Ticket ${q.ticket}.`,'info');touch();toast('s',`Walk-in #${n} added · ticket ${q.ticket}`);renderAll()}
function staffPick(id){state.staffPick=id;$('#s-code-wrap').hidden=true;$('#s-code-btn').textContent='Use a one-time code instead';showErr('s-login-err');renderStaff()}
function staffFaceId(){toast('s','Face ID recognised');setTimeout(()=>staffSignedIn('Face ID'),400)}
function staffCode(){const w=$('#s-code-wrap');if(w.hidden){state.staffCode=newCode();w.hidden=false;$('#s-code-btn').textContent='Verify code';toast('s',`Text to ${userById(state.staffPick).name.split(' ')[0]}: code ${state.staffCode}`);return}if($('#s-code').value.trim()!==state.staffCode)return showErr('s-login-err',"That code doesn't match.");staffSignedIn('one-time code')}
function staffSignedIn(how){state.staffUser=state.staffPick;const u=staffUser();$('#s-code').value='';$('#s-code-wrap').hidden=true;logAudit(actorOf(u),'auth.signin','USER-'+u.id,'Staff app · '+how);if(u.role==='clinician')state.filter=u.clin;else state.filter='all';sgo('queue')}
function staffSignOut(){const u=staffUser();logAudit(actorOf(u),'auth.signout','USER-'+u.id,'Staff app');state.staffUser=null;sgo('login')}
function sfilter(f){state.filter=f;renderStaff()}

function renderStaff(){
  const u=staffUser();
  $('#s-who').textContent=u?`${ROLES[u.role]} · ${u.name.split(' ')[u.name.startsWith('Dr.')?1:0]}`:'Signed out';
  $('#s-tabbar').hidden=!u;
  $$('#s-tabbar button').forEach(b=>b.hidden=!staffTabs().includes(b.dataset.tab));
  $('#s-accounts').innerHTML=state.users.map(x=>`<button class="choice" aria-pressed="${state.staffPick===x.id}" onclick="staffPick('${x.id}')"><div class="avatar">${initials(x.name)}</div><div class="grow"><div class="t">${esc(x.name)}</div><div class="small muted">${ROLES[x.role]}</div></div></button>`).join('');
  if(!u)return;
  // queue
  const own=u.role==='clinician';
  if(own)state.filter=u.clin;
  $('#s-filter').hidden=own;
  $('#s-filter').innerHTML=[['all','All'],...state.clins.filter(c=>capacity(c.id)>0).map(c=>[c.id,c.short])].map(([id,l])=>`<button aria-pressed="${state.filter===id}" onclick="sfilter('${id}')">${l}</button>`).join('');
  const list=state.queue.filter(q=>(state.filter==='all'||q.clin===state.filter)&&ACTIVE(q));
  $('#s-count').textContent=`${state.queue.filter(q=>q.status==='waiting').length} waiting · ${state.queue.filter(q=>q.status==='invisit').length} in visit`;
  const late=list.filter(q=>q.status==='late').sort((a,b)=>slotMin(a.time)-slotMin(b.time));const bn=$('#s-banner');bn.hidden=!late.length;
  bn.innerHTML=late.length?`<span>${esc(late[0].name)} is ${lateBy(late[0])} min late for ${ampm(late[0].time)} and not checked in.</span>${canAct(late[0])?`<div class="actions"><button class="btn sm" onclick="textPatient(${late[0].id})">Text ${esc(late[0].name.split(' ')[0])}</button><button class="btn sm" onclick="setStatus(${late[0].id},'checked')">Arrived</button><button class="btn sm" onclick="setStatus(${late[0].id},'noshow')">Mark no-show</button></div>`:''}`:'';
  $('#s-walkin').hidden=!['admin','frontdesk'].includes(u.role);
  // two lists the front desk actually works from: who is here now (arrival order), and who is still to come (by time)
  const hereOrder={invisit:0,waiting:1,checked:2};
  const here=list.filter(q=>q.status in hereOrder).sort((a,b)=>hereOrder[a.status]-hereOrder[b.status]||tnum(a.ticket)-tnum(b.ticket));
  const toCome=list.filter(q=>['late','booked','confirmed'].includes(q.status)).sort((a,b)=>slotMin(a.time)-slotMin(b.time));
  const doneL=list.filter(q=>q.status==='done');
  const nextUp=here.find(q=>q.status==='waiting'&&canAct(q))||here.find(q=>q.status==='checked'&&canAct(q));
  const row=q=>{const act=qActions(q,u,'setStatus',q===nextUp);
    const sub=q.status==='waiting'?`ticket ${q.ticket} · waiting ${waitMins(q)} min`:q.status==='invisit'?`ticket ${q.ticket} · in room`:q.status==='checked'?`ticket ${q.ticket} · arrived ${q.checkedAt}`:`${esc(q.svc)} · ${clinById(q.clin).short}${q.status==='late'?` · ${lateBy(q)} min late`:''}${q.forms?'':' · form missing'}`;
    return `<div class="qrow"><button class="qmain" onclick="state.selectedPatient=${q.id};sgo('patient')"><span class="when">${ampm(q.time)}</span><span><span class="t">${esc(q.name)}</span><span class="s">${sub}</span></span>${pill(q.status)}</button>${act?`<div class="actions">${act}</div>`:''}</div>`};
  const sec=(title,rows,empty)=>`<h3 class="qsec">${title} <span class="num">${rows.length}</span></h3><div class="qlist">${rows.map(row).join('')||`<p class="small muted" style="padding:10px 0">${empty}</p>`}</div>`;
  $('#s-queue').innerHTML=list.length?sec('Here now',here,'No one has arrived yet.')+sec('Still to arrive',toCome,'Everyone booked today has arrived.')+(doneL.length?`<details class="qdone"><summary>Completed today (${doneL.length})</summary><div class="qlist">${doneL.map(row).join('')}</div></details>`:''):'<p class="small muted">No patients for this filter.</p>';
  // schedule
  if(own)state.schedClin=u.clin;
  $('#s-sched-filter').hidden=own;
  $('#s-sched-filter').innerHTML=state.clins.filter(c=>!c.room&&capacity(c.id)>0).map(c=>`<button aria-pressed="${state.schedClin===c.id}" onclick="state.schedClin='${c.id}';renderStaff()">${c.short}</button>`).join('');
  const sc=state.schedClin,cap=capacity(sc),bk=bookedCount(sc),waits=state.queue.filter(q=>q.clin===sc&&q.status==='waiting');
  $('#s-sched-who').textContent=clinById(sc).short;
  $('#s-sched-tiles').innerHTML=`<div class="tile"><span class="eyebrow">Booked</span><b>${bk} / ${cap}</b><span class="small">${cap?Math.round(bk/cap*100):0}% utilization</span></div><div class="tile"><span class="eyebrow">Waiting now</span><b>${waits.length}</b><span class="small">target wait ≤ 10 min</span></div>`;
  $('#s-sched').innerHTML=TIMES.map(t=>{const q=apptAt(sc,t),bl=blockAt(sc,t),f=freedAt(sc,t);return `<div class="item"><span class="num muted" style="width:56px">${ampm(t)}</span><div class="grow">${q?`<div class="t">${esc(q.name)}</div><div class="s">${esc(q.svc)}</div>`:bl?`<div class="s">${bl.type}</div>`:f?`<div class="s">Freed · ${f.status==='offered'?'offered to waitlist':'open'}</div>`:'<div class="s">Open</div>'}</div>${q?pill(q.status):''}</div>`}).join('');
  // patient details
  const p=state.queue.find(q=>q.id===state.selectedPatient)||state.queue[0];const seeContact=u.role!=='support',seeIntake=u.role!=='support'&&(u.role!=='clinician'||p.clin===u.clin);
  const ik=state.intake[p.id];
  $('#s-patient').innerHTML=`<div class="card stack"><div class="row"><div class="avatar" style="width:44px;height:44px">${initials(p.name)}</div><div><h3 style="font-size:18px">${esc(p.name)}</h3><div class="small muted">${ampm(p.time)} · ${esc(p.svc)}${p.ticket?' · ticket '+p.ticket:''}</div></div><span style="margin-left:auto">${pill(p.status)}</span></div>
    <div class="grid2"><div class="tile"><span class="eyebrow">Forms</span><b style="font-size:15px">${p.forms?'Complete':'1 open'}</b></div><div class="tile"><span class="eyebrow">Phone</span><b style="font-size:15px">${seeContact&&p.phone?'… '+p.phone:'Hidden for your role'}</b></div></div>
    ${p.guardian?'<div class="tile"><span class="eyebrow">Booked by guardian</span><p class="small" style="margin-top:4px">Priya Raman gets reminders and offers for this visit.</p></div>':''}
    ${seeIntake&&ik?`<div class="tile"><span class="eyebrow">Reason for visit (operational)</span><p class="small" style="margin-top:4px">${esc(ik.type)}${ik.note?' · "'+esc(ik.note)+'"':''}</p></div>`:''}
    ${canAct(p)?`<div class="actions"><button class="btn sm" onclick="toast('s','Booking link sent by text')">Send booking link</button>${p.forms?'':`<button class="btn sm" onclick="sendForm(${p.id})">Send form</button>`}<button class="btn sm" onclick="textPatient(${p.id})">Quick text</button></div>`:''}
    <p class="small muted">Front desk and admin see contact details. Clinicians see only their own patients' operational info. Nothing clinical is stored here.</p></div>`;
  // waitlist
  $('#s-wl-count').textContent=`${state.waitlist.filter(w=>['waiting','offered'].includes(w.status)).length} waiting`;
  const f=state.freed.find(x=>x.status!=='filled')||state.freed[0];
  $('#s-freed').innerHTML=f?`<div class="row between"><div><p class="eyebrow">Freed slot · ${clinById(f.clin).short}</p><b>Tue ${ampm(f.time)}</b><div class="small muted">${f.status==='filled'?`Refilled by ${esc(f.filledBy)}`:f.status==='offered'?`Offered to ${esc(f.offers.at(-1).name)} ${fmtSecs(f.offers.at(-1).after)} after it opened · holding ${state.rules.hold} min`:f.status==='held'?'Held for a phone booking':'Open for online booking'}</div></div>${f.status==='filled'?'<span class="pill good">Recovered</span>':f.status==='offered'?'<span class="pill warn">Offer out</span>':'<span class="pill mute">Open</span>'}</div>${f.status!=='filled'&&['admin','frontdesk'].includes(u.role)?`<div class="actions" style="margin-top:10px"><button class="btn sm" onclick="toast('s','Offer sent to all matching patients')">Send to all matches</button><button class="btn sm" onclick="holdSlot('${f.id}')">Hold for phone</button></div>`:''}`:'<p class="small muted">No freed slots right now.</p>';
  $('#s-wl').innerHTML=state.waitlist.map(w=>`<div class="item"><div class="avatar">${initials(w.name)}</div><div class="grow"><div class="t">${esc(w.name)}</div><div class="s">${w.svc} · ${w.days.join('/')} · ${w.times.map(t=>({morning:'mornings',afternoon:'afternoons',after4:'after 4'}[t])).join(', ')} · ${w.clin==='any'?'any clinician':clinById(w.clin).short}</div></div>${w.priority?'<span class="pill crit">Priority</span>':''}<span class="pill ${w.status==='offered'?'warn':w.status==='booked'?'good':'mute'}">${{waiting:'Waiting',offered:'Offered',booked:'Booked',passed:'Passed'}[w.status]}</span></div>`).join('');
  $('#s-alerts').innerHTML=state.sAlerts.slice(0,30).map(n=>`<div class="item"><div class="grow"><div class="t">${esc(n.t)}</div><div class="s"><span class="kind ${n.k}">${SKIND[n.k]||'Notice'}</span> · ${n.s}</div></div></div>`).join('');
  // account
  $('#s-me-ini').textContent=initials(u.name);$('#s-me-name').textContent=u.name;$('#s-me-role').textContent=`${ROLES[u.role]} · Maple Grove Clinic`;
  $('#s-me-perms').innerHTML=({admin:['Everything, including roles and settings'],frontdesk:['Check patients in, queue and complete visits','Book, text and send forms','Answer waitlist offers'],clinician:['See and update your own patients only','Your own schedule'],support:['View the queue (read-only)','See alerts']}[u.role]).map(x=>`<li>${x}</li>`).join('');
}
const actingUser=()=>cur.surface==='web'?webUser():staffUser(), toastSide=()=>cur.surface==='web'?'w':'s';
function textPatient(id){const q=state.queue.find(x=>x.id===id),u=actingUser();deliver(q.name,'Quick text','Text','Delivered');logAudit(actorOf(u),'notification.sent','APT-'+(20900+q.id),`Quick text from the ${cur.surface==='web'?'website':'staff app'}`);toast(toastSide(),`Text sent to ${q.name.split(' ')[0]}`);renderAll()}
function remindPatient(id){const q=state.queue.find(x=>x.id===id),u=actingUser();deliver(q.name,'Reminder (manual)','Push, then text','Delivered');logAudit(actorOf(u),'notification.sent','APT-'+(20900+q.id),'Manual reminder with one-tap confirm');toast(toastSide(),`Reminder sent to ${q.name.split(' ')[0]}`);renderAll()}
function sendForm(id){const q=state.queue.find(x=>x.id===id),u=actingUser();deliver(q.name,'Intake form link','Push, then text','Delivered');logAudit(actorOf(u),'notification.sent','APT-'+(20900+q.id),'Reason-for-visit form link');if(q.mine)notifyPatient('Please complete your reason-for-visit form before your visit.','text','warn','intake');toast(cur.surface==='web'?'w':'s',`Form link sent to ${q.name.split(' ')[0]}`);renderAll()}
function holdSlot(fid){const f=state.freed.find(x=>x.id===fid),u=staffUser();f.status='held';f.offers.filter(o=>o.status==='holding').forEach(o=>o.status='withdrawn');logAudit(actorOf(u),'slot.hold','SLOT '+f.clin+' '+f.time,'Held for a phone booking');toast('s','Slot held for a phone booking');touch();renderAll()}

// ---------- staff website ----------
const PAGES={admin:['dash','cal','queue','kiosk','wait','missed','services','notif','users','audit','reports','setup'],frontdesk:['dash','cal','queue','kiosk','wait','missed','reports'],clinician:['dash','cal','queue','reports'],support:['queue']};
function webPages(){const u=webUser();return u?PAGES[u.role]:[]}
function webRO(){const u=webUser();return u&&u.role==='support'}
function webPasskey(){webSignedIn('passkey')}
function webCode(){const w=$('#w-si-code-wrap');if(w.hidden){state.webCode=newCode();w.hidden=false;$('#w-si-code-btn').textContent='Verify code';toast('w',`Email to ${userById($('#w-si-user').value).name.split(' ')[0]}: code ${state.webCode}`);return}if($('#w-si-code').value.trim()!==state.webCode)return showErr('w-si-err',"That code doesn't match. Check your email and try again.");webSignedIn('one-time code')}
function webSignedIn(how){state.webUser=$('#w-si-user').value;const u=webUser();$('#w-si-code').value='';$('#w-si-code-wrap').hidden=true;$('#w-si-code-btn').textContent='Email me a one-time code';showErr('w-si-err');logAudit(actorOf(u),'auth.signin','USER-'+u.id,'Staff website · '+how);wgo(webPages()[0])}
function webSignOut(){const u=webUser();if(u)logAudit(actorOf(u),'auth.signout','USER-'+u.id,'Staff website');state.webUser=null;renderWeb()}
// one address for the clinic everywhere: the copy button, the QR code and the admin URL
const clinicSlug=()=>state.setup.profile.name.toLowerCase().replace(/\bclinic\b/g,'').replace(/[^a-z]+/g,'')||'clinic';
const bookUrl=()=>`https://${clinicSlug()}.clinicflow.ca/book`;
function copyLink(){try{navigator.clipboard.writeText(bookUrl()).catch(()=>{})}catch(e){}toast('w',`Copied ${bookUrl().replace('https://','')}`)}
function setCalView(v){state.calView=v;renderWeb()}
function calShift(n){const d=new Date((n?cur.calDate:CAL_BASE)+'T00:00');if(n){if(state.calView==='week')d.setDate(d.getDate()+7*n);else if(state.calView==='month')d.setMonth(d.getMonth()+n);else d.setDate(d.getDate()+n)}cur.calDate=d.toLocaleDateString('en-CA');syncHash();renderWeb()}
function openDay(iso){cur.calDate=iso;state.calView='day';syncHash();renderWeb()}
function sampleCount(iso,clin){let h=0;for(const ch of iso+clin)h=(h*31+ch.charCodeAt(0))%997;const d=new Date(iso+'T00:00').getDay();if(d===0||d===6)return clin==='lam'&&d===6?6:0;if(clin==='daoud')return d===4?10:0;if(clin==='lam'&&![2,4].includes(d))return 0;return 8+h%6}
function dayCount(iso,clin){return iso===CAL_BASE?bookedCount(clin):sampleCount(iso,clin)}
function dayCap(iso,clin){if(iso===CAL_BASE)return capacity(clin);const d=new Date(iso+'T00:00').getDay();if(clin==='daoud')return d===4?14:0;if(clin==='lam')return [2,4,6].includes(d)?10:0;return d===0||d===6?0:14}
// manual booking from the calendar, with the same lock and write path as online booking
function openManualBooking(clin,time){const u=webUser();if(!u||!['admin','frontdesk'].includes(u.role))return;clin=clin||'osei';const svc=state.services.find(s=>s.clins.includes(clin))||state.services[0];state.manual={clin,time:time||null,name:'',phone:'',svc:svc.name};if(time)acquireLock(clin,time,'web',120);$('#w-book').hidden=false;renderWeb();setTimeout(()=>$('#w-mb-name')?.focus(),30)}
function manualField(k,v){const m=state.manual;m[k]=v;if(k==='svc'){const s=svcByName(v);if(!s.clins.includes(m.clin))m.clin=s.clins[0]}if(k==='clin'||k==='svc'){m.time=null;releaseLocks('web')}renderWeb()}
function manualPickTime(t){const m=state.manual;if(!t){m.time=null;releaseLocks('web');return renderWeb()}if(!acquireLock(m.clin,t,'web',120)){m.err=`${ampm(t)} is being booked online by a patient right now. Pick another time or wait for their hold to run out.`;m.time=null}else{m.err='';m.time=t}renderWeb()}
function manualConfirm(){const m=state.manual,u=webUser();m.name=$('#w-mb-name').value.trim();m.phone=digits($('#w-mb-phone').value);
  if(!m.name||m.phone.length<10||!m.time){m.err='Enter the patient name, a 10-digit phone number and a time.';return renderWeb()}
  if(!lockAt(m.clin,m.time)){m.err=`Your hold on ${ampm(m.time)} ran out. Pick the time again.`;m.time=null;return renderWeb()}
  const svc=svcByName(m.svc);const lock=lockAt(m.clin,m.time);const held=lock?Math.round((120000-(lock.until-Date.now()))/1000):0;
  const entry={name:m.name,clin:m.clin,time:m.time,svc:svc.short,svcFull:svc.name,status:'booked',forms:false,phone:m.phone.slice(-4)};
  if(!commitBooking(entry,'web')){m.err='That slot was taken a moment ago. Pick another time.';m.time=null;return renderWeb()}
  logAudit(actorOf(u),'appointment.create','APT-'+(20900+entry.id),`Manual booking · ${svc.short} · ${clinById(m.clin).short} ${ampm(m.time)} · slot lock held ${held} s`);deliver(m.name,'Booking confirmation','Text, then email','Delivered');alertStaff(`${m.name} booked by phone for ${ampm(m.time)} with ${clinById(m.clin).short}.`,'info');
  state.manual=null;$('#w-book').hidden=true;toast('w',`Booked ${entry.name} at ${ampm(entry.time)}`);renderAll()}
function manualClose(){state.manual=null;releaseLocks('web');$('#w-book').hidden=true;renderWeb()}
function runDoubleBookingTest(){
  const clin='osei',t=TIMES.find(t=>tIdx(t)>6&&slotState(clin,t,'test')==='free');if(!t){state.demoMsg='No free slot left to test with.';return renderDemo()}state.demoMsg='';
  const stamp=clock();const a={name:'Test request A (patient app)',clin,time:t,svc:'Test',status:'booked',forms:true},b={name:'Test request B (front desk)',clin,time:t,svc:'Test',status:'booked',forms:true};
  const ra=commitBooking(a,'test-a'),rb=commitBooking(b,'test-b');
  state.queue=state.queue.filter(q=>q!==a&&q!==b);const doubles=(ra&&rb)?1:0;
  state.dbTests.unshift({t:stamp,slot:`${clinById(clin).short} ${ampm(t)}`,a:ra?'Booked':'Rejected',b:rb?'Booked':'Rejected · slot already taken',doubles});
  logAudit(webUser()?actorOf(webUser()):'Presenter (demo tools)','test.concurrent_booking','SLOT '+clin+' '+t,`2 simultaneous requests · ${ra+rb} accepted · ${doubles} double bookings · test bookings removed`);
  touch();renderAll();
}
// check-in tablet: tap or type. The language choice resets with the tablet so the next patient starts fresh.
function kioskKey(k){const s=state.kiosk;if(s.step!=='enter')return;if(k==='del')s.digits=s.digits.slice(0,-1);else if(k==='clr')s.digits='';else if(s.digits.length<4)s.digits+=k;s.err='';renderWeb()}
function kioskFind(){const s=state.kiosk;if(s.digits.length<4){s.err=tl(s.lang,'k_err4');return renderWeb()}const m=state.queue.filter(q=>q.phone===s.digits&&['booked','confirmed','late'].includes(q.status));if(!m.length){s.err=tl(s.lang,'k_none');return renderWeb()}s.matches=m.map(q=>q.id);s.step='confirm';renderWeb()}
function kioskCheckIn(id){const q=state.queue.find(x=>x.id===id);checkInEntry(q,'front-desk tablet',`${q.name} (patient, tablet)`);if(q.mine)notifyPatient(`You're checked in. Ticket ${q.ticket}.`,'push','good');state.kiosk={step:'done',digits:'',ticket:q.ticket,id,lang:state.kiosk.lang};renderAll();clearTimeout(state.kioskT);state.kioskT=setTimeout(()=>{kioskReset()},8000)}
function kioskReset(){clearTimeout(state.kioskT);state.kiosk={step:'enter',digits:'',lang:'en'};renderWeb()}
function kioskLang(l){state.kiosk.lang=l;renderWeb()}
function setRule(k,v){const u=webUser();const prev=state.rules[k];state.rules[k]=v;logAudit(actorOf(u),'settings.update','CLINIC',`${k}: ${prev} → ${v}`);toast('w','Saved');renderAll()}
function runReminderJob(){
  const u=webUser();let push=0,sms=0;
  state.upcoming.forEach((p,i)=>{const fallback=i%2===1;push++;if(fallback)sms++;deliver(p.name,`Reminder, ${p.h} h`,fallback?'Push, then text':'Push',fallback?'Push not opened in 30 min; text delivered':'Delivered')});
  state.queue.filter(q=>q.status==='booked'&&ACTIVE(q)).forEach(q=>{deliver(q.name,'Same-day nudge, one-tap confirm','Push, then text','Delivered');if(q.mine)notifyPatient(`Reminder: ${q.svc} today ${ampm(q.time)} with ${clinById(q.clin).short}. Tap to confirm.`,'push','info','confirm')});
  logAudit(SYSTEM,'notification.job',`${state.upcoming.length} reminders`,`Run by ${u?u.name:'scheduler'} · 24 h and 48 h reminders · ${push} push, ${sms} text fallback`);
  state.demoMsg=`Sent ${state.upcoming.length} reminders (${push} push, ${sms} fell back to text). See Notifications, Delivery log.`;touch();renderAll();
}
function sendAnnouncement(){const t=$('#w-announce').value.trim();if(!t)return toast('w','Write the announcement first');state.notice=t;notifyPatient('Clinic notice: '+t,'push','mute');deliver('All patients with visits this week','Clinic announcement','Push, then email','Delivered to 41');logAudit(actorOf(webUser()),'notification.sent','CLINIC','Clinic announcement to 41 patients');toast('w','Announcement sent to 41 patients');renderAll()}
function addService(prefix='w'){const name=$(`#${prefix}-svc-name`).value.trim();if(!name)return toast('w','Name the service first');const dur=+$(`#${prefix}-svc-dur`).value,online=$(`#${prefix}-svc-online`).value==='1';state.services.splice(state.services.length-1,0,{name,short:name.split('·')[0].trim(),dur,buf:0,online,who:online?'New and returning':'Front desk only',form:'Contact, consent',clins:['osei','lam']});logAudit(actorOf(webUser()),'service.create','SERVICE',`${name} · ${dur} min · ${online?'bookable online':'front desk only'}`);$(`#${prefix}-svc-name`).value='';toast('w',`${name} added. Patients can book it now.`);renderAll()}
function toggleOnline(i){const s=state.services[i];s.online=!s.online;s.who=s.online?'New and returning':'Front desk only';logAudit(actorOf(webUser()),'service.update','SERVICE',`${s.name}: ${s.online?'bookable online':'front desk only'}`);renderAll()}
function addClinician(prefix='w'){const name=$(`#${prefix}-clin-name`).value.trim(),role=$(`#${prefix}-clin-role`).value.trim()||'Clinician';if(!name)return toast('w','Enter the clinician name');const id='c'+(state.nextId++);state.clins.splice(state.clins.length-1,0,{id,name,short:name.split(',')[0],role,hours:'Mon–Fri 9–5'});state.services.forEach(s=>{if(/physio/i.test(role)&&s.name.startsWith('Physio'))s.clins.push(id)});logAudit(actorOf(webUser()),'clinician.create','CLIN-'+id,`${name} · ${role}`);$(`#${prefix}-clin-name`).value='';$(`#${prefix}-clin-role`).value='';toast('w',`${name} added to the calendar`);renderAll()}
function addTimeOff(){const clin=$('#w-to-clin').value,type=$('#w-to-type').value,when=$('#w-to-when').value.trim();if(!when)return toast('w','Say when, for example "Tue 2:30" or "Oct 12–16"');state.timeoff.push({clin,type,when});const m=when.match(/^Tue (\d{1,2}:\d{2})$/i);let note='';if(m&&TIMES.includes(m[1])){if(apptAt(clin,m[1]))note=' (there is already a booking then; move it first)';else state.blocks.push({clin,time:m[1],type})}logAudit(actorOf(webUser()),'schedule.timeoff','CLIN-'+clin,`${type} · ${when}`);$('#w-to-when').value='';toast('w',`${type} added for ${clinById(clin).short}${note}`);renderAll()}
function addBlockType(){const el=$('#w-block-name'),name=el.value.trim();if(!name){toast('w','Name the type first');el.focus();return}state.blockTypes.push({name,scope:$('#w-block-who').value});el.value='';logAudit(actorOf(webUser()),'settings.update','CLINIC',`Unavailable time type added: ${name}`);toast('w',`${name} added`);renderWeb()}
function inviteUser(prefix='w'){const name=$(`#${prefix}-inv-name`).value.trim(),email=$(`#${prefix}-inv-email`).value.trim(),role=$(`#${prefix}-inv-role`).value;if(!name||!email.includes('@'))return toast('w','Enter a name and an email address');const id='u'+(state.nextId++);state.users.push({id,name,role,signin:'Invite sent · passkey on first sign-in',last:'Invited'});logAudit(actorOf(webUser()),'user.invite','USER-'+id,`${name} · ${ROLES[role]}`);$(`#${prefix}-inv-name`).value='';$(`#${prefix}-inv-email`).value='';toast('w',`Invite sent to ${email}`);renderAll()}
function setUserRole(id,role){const x=userById(id),prev=x.role;if(id===state.webUser&&role!=='admin')return toast('w',"You can't remove your own admin access");x.role=role;if(role==='clinician'&&!x.clin)x.clin='osei';logAudit(actorOf(webUser()),'role.update','USER-'+id,`${ROLES[prev]} → ${ROLES[role]}`);toast('w',`${x.name} is now ${ROLES[role]}`);renderAll()}
function missedAct(id,st){const m=state.missed.find(x=>x.id===id),prev=m.status;m.status=st;logAudit(actorOf(webUser()),'missed.'+st,m.name,`${m.date} ${m.time}`);if(st==='contacted')deliver(m.name,'Missed visit follow-up','Text, then email','Delivered');
  toast('w',{contacted:`Rebooking link sent to ${m.name.split(' ')[0]} by text`,excused:'Excused. Not counted in the no-show rate',rebooked:'Marked rebooked'}[st],st==='contacted'?null:()=>{m.status=prev;logAudit(actorOf(webUser()),'missed.undo',m.name,`Back to ${prev}`);toast('w','Undone');renderWeb()});renderWeb()}
function removeBlockType(i){const b=state.blockTypes.splice(i,1)[0];logAudit(actorOf(webUser()),'settings.update','CLINIC',`Unavailable time type removed: ${b.name}`);toast('w',`${b.name} removed`,()=>{state.blockTypes.splice(i,0,b);logAudit(actorOf(webUser()),'settings.update','CLINIC',`Unavailable time type restored: ${b.name}`);toast('w',`${b.name} restored`);renderWeb()});renderWeb()}
function tplCount(){const n=$('#w-tpl-text').value.length,seg=Math.ceil(n/160)||1;$('#w-tpl-count').textContent=`${n} characters before {placeholders} are filled · ${seg} text segment${seg>1?'s (costs more per message)':''}.`}
function saveTpl(){state.tpls[state.tplPick].text=$('#w-tpl-text').value;tplCount()}
function exportCsv(kind){
  const rows=kind==='audit'?[['Time','Actor','Action','Record','Detail'],...state.audit.map(a=>[a.t,a.actor,a.action,a.record,a.detail])]:kind==='missed'?[['Date','Time','Patient','Clinician','Reminder','Status'],...state.missed.map(m=>[m.date,m.time,m.name,m.clin,m.reminder,m.status])]:[['Clinician','Booked today','Capacity today'],...state.clins.map(c=>[c.name,bookedCount(c.id),capacity(c.id)])];
  const csv=rows.map(r=>r.map(v=>`"${String(v).replace(/"/g,'""')}"`).join(',')).join('\n');
  try{const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([csv],{type:'text/csv'}));a.download=`clinicflow-${kind}.csv`;a.click();setTimeout(()=>URL.revokeObjectURL(a.href),1000)}catch(e){}
  logAudit(actorOf(webUser()),'export.csv',kind,`${rows.length-1} rows`);toast('w',`Exported ${rows.length-1} rows`);
}
// setup wizard
const STEPS=['Clinic profile & branding','Services & durations','Clinicians & hours','Existing appointments (optional)','Booking link & QR code','Reminder & waitlist rules','Invite staff, set roles','Directory listing (optional)'];
function openSetup(n){state.setup.step=n;wgo('setup')}
function setupGo(n){state.setup.step=n;renderWeb()}
function setupNext(){const s=state.setup;if(!s.done.includes(s.step))s.done.push(s.step);if(s.step===1){s.profile.name=$('#sw-name').value.trim()||s.profile.name;s.profile.address=$('#sw-addr').value.trim();s.profile.phone=$('#sw-phone').value.trim()}
  logAudit(actorOf(webUser()),'setup.step','CLINIC',`Completed: ${STEPS[s.step-1]}`);
  if(s.step<8)s.step++;else{s.finished=Date.now();logAudit(actorOf(webUser()),'setup.complete','CLINIC',`Setup finished in ${elapsed()}`)}renderWeb()}
function setupRestart(){state.setup.step=1;state.setup.done=[];state.setup.start=Date.now();state.setup.finished=null;logAudit(actorOf(webUser()),'setup.restart','CLINIC','Timed setup test started');renderWeb()}
function elapsed(){const s=Math.round(((state.setup.finished||Date.now())-state.setup.start)/1000);return `${Math.floor(s/60)}:${String(s%60).padStart(2,'0')}`}
const BRANDS={blue:['oklch(41.6% 0.089 258)','oklch(50.3% 0.105 258)'],teal:['oklch(42% 0.07 195)','oklch(50% 0.09 195)'],green:['oklch(42% 0.08 155)','oklch(50% 0.1 155)'],plum:['oklch(40% 0.09 330)','oklch(49% 0.11 330)']};
function setBrand(b){state.setup.profile.brand=b;const [h,a]=BRANDS[b];if(b==='blue'){document.documentElement.style.removeProperty('--hero');document.documentElement.style.removeProperty('--accent')}else{document.documentElement.style.setProperty('--hero',h);document.documentElement.style.setProperty('--accent',a)}renderWeb()}
function qrSvg(url){try{if(window.qrcode){const q=qrcode(0,'M');q.addData(url);q.make();return q.createSvgTag({cellSize:4,margin:2,scalable:true})}}catch(e){}return '<div class="qr-fallback small muted">QR code needs an internet connection to draw</div>'}

function renderWeb(){
  const u=webUser();
  $('#w-signin').hidden=!!u;$('#w-app').hidden=!u;
  $('#w-user').textContent=u?`${ROLES[u.role]} · ${u.name}`:'Signed out';
  if(!$('#w-si-user').options.length)$('#w-si-user').innerHTML=state.users.map(x=>`<option value="${x.id}">${esc(x.name)} · ${ROLES[x.role]}</option>`).join('');
  if(!u)return;
  $$('.side button').forEach(b=>b.hidden=!webPages().includes(b.dataset.p));
  $$('.side .sec').forEach(s=>{let n=s.nextElementSibling,any=false;while(n&&n.tagName==='BUTTON'){if(!n.hidden)any=true;n=n.nextElementSibling}s.hidden=!any});
  if(!webPages().includes(cur.web)){return wgo(webPages()[0])}
  $$('.page').forEach(p=>p.classList.toggle('active',p.dataset.p===cur.web));setCurrent($$('.side button'),b=>b.dataset.p===cur.web);
  $('#w-ro').hidden=!webRO();
  $('#w-clinic-name').textContent=state.setup.profile.name;$('#w-url').textContent=`https://${clinicSlug()}.clinicflow.ca/admin`;
  const canBook=['admin','frontdesk'].includes(u.role);$('#w-dash-book').hidden=!canBook;
  const act=state.queue.filter(ACTIVE),clinsShown=state.clins.filter(c=>u.role!=='clinician'||c.id===u.clin);
  // dashboard
  const bookable=state.clins.filter(c=>!c.room),cap=bookable.reduce((t,c)=>t+capacity(c.id),0),bk=bookable.reduce((t,c)=>t+bookedCount(c.id),0);
  const waiting=state.queue.filter(q=>q.status==='waiting'),avgW=waiting.length?Math.round(waiting.reduce((t,q)=>t+waitMins(q),0)/waiting.length):0;
  const formsDone=act.filter(q=>q.forms).length;
  $('#w-kpis').innerHTML=`<div class="kpi"><p class="eyebrow">Booked today</p><b class="num">${bk}</b><span class="delta muted">of ${cap} slots · ${Math.round(bk/cap*100)}%</span></div><div class="kpi"><p class="eyebrow">In waiting room</p><b class="num">${waiting.length}</b><span class="delta muted">average wait ${avgW} min</span></div><div class="kpi"><p class="eyebrow">No-show rate, 30 days</p><b class="num">6.0%</b><span class="delta" style="color:var(--good)">${ic('down','ic ic-inline')} 2.3 pts vs prior 30 days</span></div><div class="kpi"><p class="eyebrow">Freed slots refilled</p><b class="num">${Math.round(state.recovery.refilled/state.recovery.total*100)}%</b><span class="delta muted">${state.recovery.refilled} of ${state.recovery.total} this month</span></div><div class="kpi"><p class="eyebrow">Intake complete</p><b class="num">${formsDone} / ${act.length}</b><span class="delta" style="color:var(--warn)">${act.length-formsDone} forms open</span></div>`;
  const attn=[];
  state.queue.filter(q=>q.status==='late').forEach(q=>attn.push(`<tr><td>${pill('late')}</td><td>${esc(q.name)} · ${ampm(q.time)} with ${clinById(q.clin).short}</td><td class="muted">${lateBy(q)} min late, not checked in</td><td>${canBook?`<button class="btn sm" onclick="textPatient(${q.id})">Text</button> <button class="btn sm" onclick="webStatus(${q.id},'checked')">Arrived</button> <button class="btn sm danger" onclick="webStatus(${q.id},'noshow')">No-show</button>`:''}</td></tr>`));
  state.freed.filter(f=>f.status==='offered'||f.status==='open').forEach(f=>attn.push(`<tr><td><span class="pill warn">Offer</span></td><td>${ampm(f.time)} with ${clinById(f.clin).short} freed</td><td class="muted">${f.status==='offered'?`offered to ${esc(f.offers.at(-1).name)}`:'open for booking'}</td><td><button class="btn sm" onclick="wgo('wait')">View</button></td></tr>`));
  const unconf=act.filter(q=>q.status==='booked');if(unconf.length)attn.push(`<tr><td><span class="pill mute">Unconfirmed</span></td><td>${unconf.length} visits today not confirmed</td><td class="muted">reminders sent Sun and Mon</td><td>${canBook?`<button class="btn sm" onclick="unconfirmedRemind()">Remind all</button>`:''}</td></tr>`);
  const noForm=act.filter(q=>!q.forms&&!['done','invisit'].includes(q.status));if(noForm.length)attn.push(`<tr><td><span class="pill warn">Forms</span></td><td>${noForm.length} patients missing reason-for-visit</td><td class="muted">auto-nudge at 8:30 am</td><td>${canBook?`<button class="btn sm" onclick="formsAll()">Resend</button>`:''}</td></tr>`);
  if(u.role==='admin')attn.push(`<tr><td><span class="pill info">Setup</span></td><td>French text templates</td><td class="muted">3 of 10 not translated</td><td><button class="btn sm" onclick="wgo('notif')">Fix</button></td></tr>`);
  $('#w-attn').innerHTML=attn.join('')||'<tr><td class="muted">Nothing needs attention.</td></tr>';$('#w-attn-count').textContent=attn.length;
  const util=bookable.filter(c=>capacity(c.id)>0).map(c=>{const p=Math.round(bookedCount(c.id)/capacity(c.id)*100);return `<div class="bar"><span>${esc(c.name)}</span><i ${p<50?'class="warn"':''} style="--w:${p}%"></i><span class="num muted">${p}%</span></div>`}).join('');
  $('#w-util').innerHTML=util;
  // calendar
  const d=new Date(cur.calDate+'T00:00'),v=state.calView;
  $$('#w-cal-view button').forEach(b=>b.setAttribute('aria-pressed',b.dataset.v===v));
  $('#w-book-btn').hidden=!canBook;
  const wk0=new Date(d);wk0.setDate(d.getDate()-((d.getDay()+6)%7));
  const iso=x=>x.toLocaleDateString('en-CA'),fmt=(x,o)=>x.toLocaleDateString('en-CA',o);
  $('#w-cal-date').textContent=v==='day'?fmt(d,{weekday:'long',month:'short',day:'numeric'}):v==='week'?`Week of ${fmt(wk0,{month:'short',day:'numeric'})}`:fmt(d,{month:'long',year:'numeric'});
  $('#w-cal-note').hidden=v!=='day'||cur.calDate===CAL_BASE;
  let html='';
  if(v==='day'){
    const isToday=cur.calDate===CAL_BASE;
    html=`<div class="cal" style="grid-template-columns:72px repeat(${clinsShown.length},minmax(120px,1fr));min-width:${72+clinsShown.length*130}px"><div class="h"></div>${clinsShown.map(c=>`<div class="h">${esc(c.short)}<small>${esc(c.role)}</small></div>`).join('')}`;
    TIMES.forEach(t=>{html+=`<div class="time">${ampm(t)}</div>`;clinsShown.forEach(c=>{let cell='';
      if(!isToday){const n=sampleCount(cur.calDate,c.id),cp=dayCap(cur.calDate,c.id);cell=!cp?'<div class="appt off">Not in</div>':((tIdx(t)*7+n)%14)<n?'<div class="appt">Booked</div>':''}
      else{const q=apptAt(c.id,t),bl=blockAt(c.id,t),l=lockAt(c.id,t),f=freedAt(c.id,t);
        if(q){const dur=(state.services.find(s=>s.name===q.svcFull||s.short===q.svc)||{dur:30}).dur;cell=`<div class="appt st ${STATUS[q.status][0]}${dur>30?' long':''}" title="${esc(q.name)} · ${esc(q.svc)} · ${dur} min · ${STATUS[q.status][1]}"><b>${esc(q.name)}</b>${STATUS[q.status][1]}${dur>30?` · ${dur} min`:''}</div>`}
        else if(bl)cell=`<div class="appt off">${bl.type}</div>`;
        else if(l)cell=`<div class="appt warn">${ic('lock','ic ic-inline')} Held · ${l.owner==='patient'?'patient online':'front desk'}</div>`;
        else if(f)cell=`<div class="appt freed">Freed · ${f.status==='offered'?'offered':f.status==='held'?'held for phone':'open'}</div>`;
        else if(canBook)cell=`<button class="cal-add" onclick="openManualBooking('${c.id}','${t}')" aria-label="Book ${c.short} at ${ampm(t)}">+</button>`}
      html+=`<div class="cell">${cell}</div>`})});
    html+='</div>';
  }else if(v==='week'){
    const days=[0,1,2,3,4,5].map(i=>{const x=new Date(wk0);x.setDate(wk0.getDate()+i);return x});
    html=`<table class="weekgrid"><tr><th>Clinician</th>${days.map(x=>`<th><button class="btn sm" onclick="openDay('${iso(x)}')">${fmt(x,{weekday:'short',day:'numeric'})}</button></th>`).join('')}</tr>${clinsShown.filter(c=>!c.room).map(c=>`<tr><td>${esc(c.short)}</td>${days.map(x=>{const cp=dayCap(iso(x),c.id),n=Math.min(cp,dayCount(iso(x),c.id));return `<td>${cp?`<div class="num">${n} / ${cp}</div><i class="mini" style="--w:${Math.round(n/cp*100)}%"></i>`:'<span class="muted small">Not in</span>'}</td>`}).join('')}</tr>`).join('')}</table>`;
  }else{
    const first=new Date(d.getFullYear(),d.getMonth(),1),start=new Date(first);start.setDate(1-((first.getDay()+6)%7));
    html='<div class="monthgrid">'+['Mon','Tue','Wed','Thu','Fri','Sat','Sun'].map(x=>`<div class="mh">${x}</div>`).join('');
    for(let i=0;i<42;i++){const x=new Date(start);x.setDate(start.getDate()+i);const ix=iso(x),inM=x.getMonth()===d.getMonth(),tot=clinsShown.filter(c=>!c.room).reduce((t,c)=>t+Math.min(dayCap(ix,c.id),dayCount(ix,c.id)),0),closed=x.getDay()===0;
      html+=`<button class="md ${inM?'':'out'} ${ix===CAL_BASE?'today':''}" onclick="openDay('${ix}')"><span>${x.getDate()}</span><small>${closed?'Closed':tot+' booked'}</small></button>`}
    html+='</div>';
  }
  $('#w-cal-body').innerHTML=html;
  const m=state.manual;$('#w-book').hidden=!m;
  if(m){const free=TIMES.filter(t=>{const s=slotState(m.clin,t,'web');return s==='free'||s==='freed'||t===m.time});const svcM=svcByName(m.svc);
    $('#w-book').innerHTML=`<div class="row between"><h3>New booking (front desk)</h3><button class="btn sm ghost" onclick="manualClose()">Close</button></div><div class="form-row">
      <label class="fl">Patient name<input class="btn sm" id="w-mb-name" autocomplete="off" value="${esc(m.name)}" oninput="state.manual.name=this.value"></label>
      <label class="fl">Mobile number<input class="btn sm" id="w-mb-phone" inputmode="tel" autocomplete="off" value="${esc(m.phone)}" oninput="state.manual.phone=this.value"></label>
      <label class="fl">Service<select class="btn sm" id="w-mb-svc" onchange="manualField('svc',this.value)">${state.services.map(s=>`<option value="${esc(s.name)}" ${s.name===m.svc?'selected':''}>${esc(s.short)} · ${s.dur} min</option>`).join('')}</select></label>
      <label class="fl">Clinician<select class="btn sm" id="w-mb-clin" onchange="manualField('clin',this.value)">${state.clins.filter(c=>svcM.clins.includes(c.id)).map(c=>`<option value="${c.id}" ${c.id===m.clin?'selected':''}>${esc(c.short)}</option>`).join('')}</select></label>
      <label class="fl">Time<select class="btn sm" id="w-mb-time" onchange="manualPickTime(this.value)"><option value="">Choose…</option>${TIMES.map(t=>{const s=slotState(m.clin,t,'web');const ok=s==='free'||s==='freed'||t===m.time;return `<option value="${t}" ${t===m.time?'selected':''} ${ok?'':'disabled'}>${ampm(t)}${ok?'':' · '+({taken:'taken',blocked:'unavailable',held:'held online',offered:'offered to waitlist'}[s]||'')}</option>`}).join('')}</select></label>
      <button class="btn sm primary" onclick="manualConfirm()">Book</button></div><p class="small lockbar" id="w-mb-lock" hidden>${ic('lock','ic ic-inline')}<span></span></p>${m.err?`<p class="err" role="alert">${esc(m.err)}</p>`:''}<p class="small muted">${free.length} open times with ${clinById(m.clin).short} today.</p>`;
    updateLocks()}
  // live queue and TV board
  // the same actions as the staff app, so the front desk can run the queue from either
  const qo={invisit:0,waiting:1,checked:2,late:3,done:4};
  const arrived=state.queue.filter(q=>q.status in qo&&(u.role!=='clinician'||q.clin===u.clin)).sort((a,b)=>qo[a.status]-qo[b.status]||tnum(a.ticket)-tnum(b.ticket)||slotMin(a.time)-slotMin(b.time));
  const wNext=arrived.find(q=>q.status==='waiting'&&canAct(q,u));
  $('#w-queue').innerHTML='<tr><th>Ticket</th><th>Patient</th><th>Appt</th><th>Status</th><th>Waited</th><th>Forms</th><th><span class="sr">Actions</span></th></tr>'+arrived.map(q=>`<tr><td class="num">${q.ticket||'—'}</td><td>${esc(q.name)}<div class="small muted">${clinById(q.clin).short}</div></td><td class="num">${ampm(q.time)}</td><td>${pill(q.status)}</td><td class="num">${q.status==='waiting'?waitMins(q)+' min':q.status==='late'?lateBy(q)+' min late':''}</td><td>${q.forms?'<span class="pill good">Done</span>':'<span class="pill warn">Open</span>'}</td><td><div class="actions" style="gap:var(--space-xs);flex-wrap:nowrap">${qActions(q,u,'webStatus',q===wNext)}</div></td></tr>`).join('');
  const nextT=state.queue.filter(q=>q.status==='waiting').map(q=>q.ticket).sort((a,b)=>tnum(a)-tnum(b)).slice(0,3);
  $('#w-tv').innerHTML=`<p class="eyebrow" style="color:inherit;opacity:.7">Now serving</p><div class="now">${nowServing()||'—'}</div><div class="up">${nextT.length?nextT.map((t,i)=>`<span>${i?'':'Next: '}${t}</span>`).join(''):'<span>No one waiting</span>'}</div><p class="small" style="opacity:.7;margin-top:12px">Ticket numbers only. No names on the board.</p>`;
  // kiosk
  const k=state.kiosk,kt=(key,v)=>tl(k.lang,key,v),kl=`<div class="seg lang" role="group" aria-label="Language / Langue">${langSwitch(k.lang,'kioskLang')}</div>`;
  $('#w-kiosk').innerHTML=k.step==='enter'?`<div class="kiosk-screen" lang="${k.lang}">${kl}<h3>${kt('k_welcome',{name:esc(state.setup.profile.name)})}</h3><p class="muted">${kt('k_intro')}</p><div class="kiosk-digits" aria-live="polite" aria-label="${k.digits.length} of 4">${[0,1,2,3].map(i=>`<span>${k.digits[i]||''}</span>`).join('')}</div><div class="keypad">${['1','2','3','4','5','6','7','8','9','clr','0','del'].map(x=>`<button onclick="kioskKey('${x}')" aria-label="${x==='del'?kt('k_del'):x==='clr'?kt('k_clear'):x}">${x==='del'?ic('left'):x==='clr'?kt('k_clear'):x}</button>`).join('')}</div>${k.err?`<p class="err" role="alert">${esc(k.err)}</p>`:''}<button class="btn primary block" onclick="kioskFind()">${tl(k.lang,'continue')}</button></div>`
    :k.step==='confirm'?`<div class="kiosk-screen" lang="${k.lang}"><h3>${kt('k_isYou')}</h3><div class="stack">${k.matches.map(id=>{const q=state.queue.find(x=>x.id===id);return `<button class="choice" onclick="kioskCheckIn(${id})"><div class="avatar" aria-hidden="true">${initials(q.name)}</div><div class="grow"><div class="t">${initials(q.name).split('').join('. ')}.</div><div class="small muted">${kt('k_with',{time:fmtT(q.time,k.lang),who:clinById(q.clin).short})}</div></div></button>`}).join('')}</div><button class="btn block" onclick="kioskReset()">${kt('k_notMe')}</button><p class="small muted">${kt('k_privacy')}</p></div>`
    :`<div class="kiosk-screen ticket-card" lang="${k.lang}"><h3>${kt('k_done')}</h3><b class="ticket">${k.ticket}</b><p class="small muted">${kt('k_ticket')}</p><button class="btn block" onclick="kioskReset()">${kt('k_finish')}</button></div>`;
  // waitlist and recovery
  $('#w-wait-kpis').innerHTML=`<div class="kpi"><p class="eyebrow">Freed slots refilled</p><b class="num">${state.recovery.refilled} / ${state.recovery.total}</b><span class="delta muted">${Math.round(state.recovery.refilled/state.recovery.total*100)}% recovery</span></div><div class="kpi"><p class="eyebrow">Fastest offer today</p><b class="num">${fmtSecs(Math.min(...state.freed.flatMap(f=>f.offers.map(o=>o.after)),9999)||0)}</b><span class="delta" style="color:var(--good)">target under 5 min</span></div><div class="kpi"><p class="eyebrow">On the waitlist</p><b class="num">${state.waitlist.filter(w=>['waiting','offered'].includes(w.status)).length}</b><span class="delta muted">${state.waitlist.filter(w=>w.priority).length} flagged priority</span></div>`;
  $('#w-offers').innerHTML='<tr><th>Slot</th><th>Freed</th><th>Offered to</th><th>Sent after</th><th>Status</th></tr>'+state.freed.map(f=>{const o=f.offers.at(-1);return `<tr><td>${clinById(f.clin).short} ${ampm(f.time)}</td><td class="num">${f.freedClock} · ${esc(f.reason)}</td><td>${o?esc(o.name):'—'}${f.offers.length>1?` <span class="small muted">(${f.offers.length} tries)</span>`:''}</td><td class="num">${o?fmtSecs(o.after)+(o.after<300?' <span class="small" style="color:var(--good)">on target</span>':''):'—'}</td><td>${f.status==='filled'?`<span class="pill good">Refilled · ${esc(f.filledBy)}</span>`:f.status==='offered'?`<span class="pill warn">Holding · ${state.rules.hold} min</span>`:f.status==='held'?'<span class="pill mute">Held for phone</span>':'<span class="pill mute">Open online</span>'}</td></tr>`}).join('');
  const ro=u.role!=='admin';
  $('#w-rules').innerHTML=`<div class="field"><label for="r-cw">Cancellation window</label><select id="r-cw" ${ro?'disabled':''} onchange="setRule('cancelWindow',+this.value)">${[12,24,48].map(x=>`<option value="${x}" ${state.rules.cancelWindow===x?'selected':''}>${x} hours</option>`).join('')}</select></div><div class="field"><label for="r-or">Offer order</label><select id="r-or" ${ro?'disabled':''} onchange="setRule('order',this.value)">${['First come, first served (staff can pin priority)','Priority first, then time joined'].map(x=>`<option ${state.rules.order===x?'selected':''}>${x}</option>`).join('')}</select></div><div class="field"><label for="r-ho">Offer hold time</label><select id="r-ho" ${ro?'disabled':''} onchange="setRule('hold',+this.value)">${[15,30,60].map(x=>`<option value="${x}" ${state.rules.hold===x?'selected':''}>${x} minutes</option>`).join('')}</select></div><div class="field"><label for="r-cu">Same-day online booking cutoff</label><select id="r-cu" ${ro?'disabled':''} onchange="setRule('cutoff',this.value)">${['60 min before slot','2 h before slot','Not allowed'].map(x=>`<option ${state.rules.cutoff===x?'selected':''}>${x}</option>`).join('')}</select></div>${ro?'<p class="small muted">Only an admin can change these rules.</p>':''}`;
  $('#w-wl').innerHTML='<tr><th>Patient</th><th>Service</th><th>When they can come</th><th>Clinician</th><th>Joined</th><th>Status</th></tr>'+state.waitlist.map(w=>`<tr><td>${esc(w.name)}${w.priority?' <span class="pill crit">Priority</span>':''}</td><td>${w.svc}</td><td class="small">${w.days.join('/')} · ${w.times.map(t=>({morning:'mornings',afternoon:'afternoons',after4:'after 4'}[t])).join(', ')}</td><td class="muted">${w.clin==='any'?'Any':clinById(w.clin).short}</td><td class="muted">${w.joined}</td><td><span class="pill ${w.status==='offered'?'warn':w.status==='booked'?'good':'mute'}">${{waiting:'Waiting',offered:'Offered',booked:'Booked',passed:'Passed'}[w.status]}</span></td></tr>`).join('');
  // missed visits
  const M={open:['crit','Needs follow-up'],contacted:['warn','Contacted'],rebooked:['good','Rebooked'],excused:['mute','Excused']};const open=state.missed.filter(x=>x.status==='open').length;
  $('#w-missed-kpis').innerHTML=`<div class="kpi"><p class="eyebrow">Missed, 30 days</p><b class="num">${state.missed.length}</b><span class="delta muted">${state.missed.filter(x=>x.status==='excused').length} excused</span></div><div class="kpi"><p class="eyebrow">Need follow-up</p><b class="num">${open}</b><span class="delta" style="color:var(${open?'--warn':'--good'})">${open?'send a rebooking link':'all handled'}</span></div><div class="kpi"><p class="eyebrow">Rebooked</p><b class="num">${state.missed.filter(x=>x.status==='rebooked').length}</b><span class="delta muted">of ${state.missed.length} missed</span></div><div class="kpi"><p class="eyebrow">Repeat no-shows</p><b class="num">${state.missed.filter(x=>x.prior>0).length}</b><span class="delta muted">missed before</span></div>`;
  $$('#w-missed-filter button').forEach((b,i)=>b.setAttribute('aria-pressed',(i===0)===(state.missedFilter==='open')));
  const mr=state.missed.filter(x=>state.missedFilter==='all'||x.status==='open'||x.status==='contacted');
  $('#w-missed').innerHTML='<tr><th>Missed</th><th>Patient</th><th>Clinician</th><th>Reminder</th><th>Status</th><th></th></tr>'+(mr.length?mr.map(x=>`<tr><td class="num" style="white-space:nowrap">${x.date} · ${x.time}</td><td>${esc(x.name)}${x.prior?` <span class="pill crit">${x.prior+1}× missed</span>`:''}<div class="small muted">${esc(x.svc)}</div></td><td class="muted">${x.clin}</td><td class="small">${x.reminder}</td><td><span class="pill ${M[x.status][0]}">${M[x.status][1]}</span></td><td style="white-space:nowrap">${x.status==='open'?`<button class="btn sm primary" onclick="missedAct(${x.id},'contacted')">Send rebooking link</button> <button class="btn sm" onclick="missedAct(${x.id},'excused')">Excuse</button>`:x.status==='contacted'?`<button class="btn sm" onclick="missedAct(${x.id},'rebooked')">Mark rebooked</button>`:''}</td></tr>`).join(''):'<tr><td colspan="6" class="muted">Nothing to follow up. Switch to All to see handled visits.</td></tr>');
  // services, clinicians, time off
  $('#w-services').innerHTML='<tr><th>Service</th><th>Length</th><th>Buffer</th><th>Online</th><th>Intake form</th></tr>'+state.services.map((s,i)=>`<tr><td>${esc(s.name)}</td><td class="num">${s.dur} min</td><td class="num">${s.buf} min</td><td><button class="btn sm" onclick="toggleOnline(${i})">${s.online?'Bookable online':'Front desk only'}</button></td><td class="small">${s.form}</td></tr>`).join('');
  $('#w-clins').innerHTML=state.clins.map(c=>`<div class="item"><div class="avatar">${initials(c.name)}</div><div class="grow"><div class="t">${esc(c.name)}</div><div class="s">${esc(c.role)} · ${c.hours}${state.timeoff.filter(t=>t.clin===c.id&&t.type==='Vacation').map(t=>' · off '+t.when).join('')}</div></div><span class="pill ${c.visiting?'mute':'good'}">${c.visiting?'Visiting':c.room?'Room':'Active'}</span></div>`).join('');
  $('#w-timeoff').innerHTML='<tr><th>Clinician</th><th>Type</th><th>When</th></tr>'+state.timeoff.map(t=>`<tr><td>${clinById(t.clin).short}</td><td>${t.type}</td><td>${esc(t.when)}</td></tr>`).join('');
  const toClin=$('#w-to-clin').value;$('#w-to-clin').innerHTML=state.clins.map(c=>`<option value="${c.id}" ${c.id===toClin?'selected':''}>${esc(c.short)}</option>`).join('');
  const toType=$('#w-to-type').value;$('#w-to-type').innerHTML=state.blockTypes.map(b=>`<option ${b.name===toType?'selected':''}>${esc(b.name)}</option>`).join('');
  $('#w-blocks').innerHTML='<tr><th>Type</th><th>Applies to</th><th>On the calendar</th><th></th></tr>'+state.blockTypes.map((b,i)=>`<tr><td>${esc(b.name)}</td><td class="muted">${b.scope}</td><td style="width:140px"><div class="appt off" style="height:22px">${esc(b.name)}</div></td><td style="text-align:right"><button class="btn sm danger" onclick="removeBlockType(${i})" aria-label="Remove ${esc(b.name)}">Remove</button></td></tr>`).join('');
  // notifications
  const pick=$('#w-tpl-pick');if(!pick.options.length)pick.innerHTML=Object.entries(state.tpls).map(([key,t])=>`<option value="${key}">${t.label}</option>`).join('');pick.value=state.tplPick;
  const ta=$('#w-tpl-text');if(document.activeElement!==ta)ta.value=state.tpls[state.tplPick].text;tplCount();
  $('#w-deliveries').innerHTML='<tr><th>Time</th><th>To</th><th>Message</th><th>Channel</th><th>Outcome</th></tr>'+state.deliveries.slice(0,40).map(x=>`<tr><td class="num">${x.t}</td><td>${esc(x.to)}</td><td>${x.msg}</td><td class="small">${x.ch}</td><td class="small">${x.out}</td></tr>`).join('');
  // users
  $('#w-users').innerHTML='<tr><th>Name</th><th>Role</th><th>Sign-in</th><th>Last active</th></tr>'+state.users.map(x=>`<tr><td>${esc(x.name)}${x.id===state.webUser?' <span class="small muted">(you)</span>':''}</td><td><select class="btn sm" onchange="setUserRole('${x.id}',this.value)" aria-label="Role for ${esc(x.name)}">${Object.entries(ROLES).map(([r,l])=>`<option value="${r}" ${x.role===r?'selected':''}>${l}</option>`).join('')}</select></td><td class="small">${x.signin}</td><td class="num">${x.last}</td></tr>`).join('');
  // audit
  const fq=($('#w-audit-filter').value||'').toLowerCase();const rows=state.audit.filter(a=>!fq||(a.actor+a.action+a.record+a.detail).toLowerCase().includes(fq));
  $('#w-audit-count').textContent=`${rows.length} of ${state.audit.length} entries · every booking, change, sign-in and message is recorded here`;
  $('#w-audit').innerHTML='<tr><th>Time</th><th>Actor</th><th>Action</th><th>Record</th><th>Detail</th></tr>'+rows.slice(0,200).map(a=>`<tr><td>${a.t}</td><td>${esc(a.actor)}</td><td class="mono-sm">${a.action}</td><td class="small">${esc(a.record)}</td><td class="small">${esc(a.detail)}</td></tr>`).join('');
  // reports
  const todayN=act.length,vals=[['Mon',31],['Tue',todayN],['Wed',26],['Thu',29],['Fri',22]],mx=Math.max(...vals.map(x=>x[1]));
  $('#w-rep-day').innerHTML=vals.map(([dName,n])=>`<div class="vbar ${dName==='Tue'?'today':''}"><span class="num">${n}</span><i style="--h:${Math.round(n/mx*100)}%"></i><span>${dName}${dName==='Tue'?' (today)':''}</span></div>`).join('');
  $('#w-rep-util').innerHTML=util;
  $('#w-rep-fill').textContent=Math.round(state.recovery.refilled/state.recovery.total*100)+'%';
  $('#w-rep-fill-sub').textContent=`of freed slots refilled (${state.recovery.refilled} of ${state.recovery.total}) · median 38 min to refill`;
  $('#w-rep-wait').textContent=`${avgW||9} min`;
  // setup wizard
  const s=state.setup;
  $('#w-setup-timer').textContent=s.finished?`Finished in ${elapsed()}`:`Setup time ${elapsed()}`;
  $('#w-steps').innerHTML=STEPS.map((l,i)=>{const n=i+1;return `<li class="${s.done.includes(n)?'done':''} ${s.step===n?'now':''}"><button onclick="setupGo(${n})"><i>${s.done.includes(n)?ic('check'):n}</i>${l}</button></li>`}).join('');
  const P=s.profile,url=bookUrl();
  const bodies={
    1:`<h3>Clinic profile and branding</h3><div class="form-grid"><div class="field"><label for="sw-name">Clinic name</label><input id="sw-name" value="${esc(P.name)}"></div><div class="field"><label for="sw-phone">Phone</label><input id="sw-phone" value="${esc(P.phone)}"></div><div class="field"><label for="sw-addr">Address</label><input id="sw-addr" value="${esc(P.address)}"></div><div class="field"><label>Brand colour</label><div class="swatches">${Object.keys(BRANDS).map(b=>`<button class="swatch ${P.brand===b?'on':''}" style="background:${BRANDS[b][0]}" onclick="setBrand('${b}')" aria-label="${b}" aria-pressed="${P.brand===b}"></button>`).join('')}</div></div></div><p class="small muted">One location for now. Patients see this name, address and colour on the booking page and in messages.</p>`,
    2:`<h3>Services and how long they take</h3><div class="list">${state.services.map(x=>`<div class="item"><div class="grow"><div class="t">${esc(x.name)}</div><div class="s">${x.dur} min · ${x.online?'bookable online':'front desk only'}</div></div></div>`).join('')}</div><div class="form-row"><label class="fl">New service<input class="btn sm" id="sw-svc-name" placeholder="e.g. Massage · 60 min"></label><label class="fl">Length (min)<select class="btn sm" id="sw-svc-dur"><option>15</option><option selected>30</option><option>45</option><option>60</option></select></label><label class="fl">Booking<select class="btn sm" id="sw-svc-online"><option value="1">Bookable online</option><option value="0">Front desk only</option></select></label><button class="btn sm" onclick="addService('sw')">Add service</button></div>`,
    3:`<h3>Clinicians and their hours</h3><div class="list">${state.clins.map(c=>`<div class="item"><div class="avatar">${initials(c.name)}</div><div class="grow"><div class="t">${esc(c.name)}</div><div class="s">${esc(c.role)} · ${c.hours}</div></div></div>`).join('')}</div><div class="form-row"><label class="fl">Name<input class="btn sm" id="sw-clin-name" autocomplete="off"></label><label class="fl">Role<input class="btn sm" id="sw-clin-role" placeholder="e.g. Physiotherapist"></label><button class="btn sm" onclick="addClinician('sw')">Add clinician</button></div><p class="small muted">Breaks and time off can be added later under Services &amp; clinicians.</p>`,
    4:`<h3>Existing appointments (optional)</h3><p class="small muted">No spreadsheet is needed to finish setup.</p><div class="stack">${[['fresh','Start fresh: patients book through your link from now on (recommended)'],['hand','Add upcoming appointments by hand in the Calendar'],['file','Upload a calendar export (.ics) later']].map(([k,l])=>`<label class="chk"><input type="radio" name="sw-ex" ${s.existing===k?'checked':''} onchange="state.setup.existing='${k}'"><span class="small">${l}</span></label>`).join('')}</div>`,
    5:`<h3>Your public booking link</h3><div class="row" style="flex-wrap:wrap"><code class="tpl" style="flex:1;min-width:200px">${url.replace('https://','')}</code><button class="btn sm" onclick="copyLink()">Copy</button></div><div class="row" style="gap:16px;align-items:flex-start;flex-wrap:wrap"><div class="qr">${qrSvg(url)}</div><div class="small stack" style="flex:1;min-width:200px"><p>Print this for the front desk, the door and appointment cards. Patients scan it, pick a time and confirm with a text code. No app or account needed.</p><div class="row"><button class="btn sm" onclick="surface('patient',$$('.switch button')[0]);startBooking()">Open it as a patient</button></div></div></div>`,
    6:`<h3>Reminder and waitlist rules</h3><label class="chk"><input type="checkbox" ${state.rules.remind48?'checked':''} onchange="setRule('remind48',this.checked)"><span class="small">Reminder 48 hours before, with one-tap confirm (push, then email)</span></label><label class="chk"><input type="checkbox" ${state.rules.remind24?'checked':''} onchange="setRule('remind24',this.checked)"><span class="small">Reminder 24 hours before (push, then text)</span></label><div class="form-grid"><div class="field"><label for="sw-cw">Cancellation window</label><select id="sw-cw" onchange="setRule('cancelWindow',+this.value)">${[12,24,48].map(x=>`<option value="${x}" ${state.rules.cancelWindow===x?'selected':''}>${x} hours</option>`).join('')}</select></div><div class="field"><label for="sw-ho">Waitlist offer holds for</label><select id="sw-ho" onchange="setRule('hold',+this.value)">${[15,30,60].map(x=>`<option value="${x}" ${state.rules.hold===x?'selected':''}>${x} minutes</option>`).join('')}</select></div></div>`,
    7:`<h3>Invite your staff</h3><div class="list">${state.users.map(x=>`<div class="item"><div class="avatar">${initials(x.name)}</div><div class="grow"><div class="t">${esc(x.name)}</div><div class="s">${ROLES[x.role]} · ${x.last}</div></div></div>`).join('')}</div><div class="form-row"><label class="fl">Name<input class="btn sm" id="sw-inv-name" autocomplete="off"></label><label class="fl">Email<input class="btn sm" id="sw-inv-email" type="email" autocomplete="off"></label><label class="fl">Role<select class="btn sm" id="sw-inv-role"><option value="frontdesk">Front desk</option><option value="clinician">Clinician</option><option value="support">Support</option><option value="admin">Admin</option></select></label><button class="btn sm" onclick="inviteUser('sw')">Invite</button></div>`,
    8:`<h3>ClinicFlow directory (optional)</h3><label class="chk"><input type="checkbox" ${s.listed?'checked':''} onchange="state.setup.listed=this.checked;renderWeb()"><span class="small">List ${esc(P.name)} so nearby patients can find openings</span></label>${s.listed?`<div class="item card"><div class="avatar">${initials(P.name)}</div><div class="grow"><div class="t">${esc(P.name)}</div><div class="s">${esc(P.address)} · ${state.services.filter(x=>x.online).length} services online · next opening today 2:30 pm</div></div></div>`:''}<p class="small muted">Only availability is shared. Never patient names or reasons for visits.</p>`,
  };
  $('#w-step-body').innerHTML=bodies[s.step]+(s.finished&&s.step===8?`<div class="banner good-banner">Setup complete in ${elapsed()}. The target is under 60 minutes.</div>`:'')+`<div class="row between" style="margin-top:6px"><button class="btn ghost" onclick="setupGo(${Math.max(1,s.step-1)})" ${s.step===1?'disabled':''}>Back</button><button class="btn primary" onclick="setupNext()">${s.step===8?'Finish setup':'Save and continue'}</button></div>`;
  renderDemo();
}
function unconfirmedRemind(){state.queue.filter(q=>q.status==='booked').forEach(q=>remindPatient(q.id));toast('w','Reminders sent')}
function formsAll(){state.queue.filter(q=>ACTIVE(q)&&!q.forms&&!['done','invisit'].includes(q.status)).forEach(q=>sendForm(q.id));toast('w','Form links sent')}

// ---------- theme ----------
function syncThemeButton(){const dark=document.documentElement.dataset.theme==='dark';$('#theme-toggle').setAttribute('aria-pressed',dark);$('#theme-label').textContent=dark?'Light mode':'Dark mode'}
function toggleTheme(){const dark=document.documentElement.dataset.theme!=='dark';if(dark)document.documentElement.dataset.theme='dark';else delete document.documentElement.dataset.theme;try{localStorage.setItem('cf-theme',dark?'dark':'light')}catch(e){}syncThemeButton()}

// ---------- demo tools: presenter shortcuts that stay out of the product screens ----------
function toggleDemo(){const d=$('#demo'),open=d.hidden;d.hidden=!open;$('#demo-toggle').setAttribute('aria-expanded',open);if(open){renderDemo();$('#demo-h').tabIndex=-1;$('#demo-h').focus()}else $('#demo-toggle').focus()}
function demoKiosk(d){state.kiosk={step:'enter',digits:d,lang:state.kiosk.lang};surface('web',$$('.switch button')[2]);wgo('kiosk');if(!state.webUser)state.demoMsg='Sign in to the website (front desk or admin) to see the tablet.';renderDemo()}
function demoFillCode(){if(cur.patient!=='otp'||!state.otp.code)return;fillCode();$$('#p-otp input')[5].focus()}
function renderDemo(){
  const el=$('#demo-body');if(!el||$('#demo').hidden)return;
  const tests=state.dbTests,doubles=tests.reduce((t,x)=>t+x.doubles,0),onOtp=cur.surface==='patient'&&cur.patient==='otp'&&state.otp.code;
  el.innerHTML=`<h3>Patient app</h3><div class="actions"><button class="btn sm" onclick="demoFillCode()" ${onOtp?'':'disabled'}>Fill the texted code</button></div><p class="small muted">${onOtp?'Fills the 6 boxes on the code step.':'Works on the "Verify your phone" step.'}</p>
    <h3>Double-booking guard</h3><p class="small muted">Sends two bookings for the same slot at the same moment. The write path accepts one and rejects the other.</p><div class="actions"><button class="btn sm primary" onclick="runDoubleBookingTest()">Run concurrent booking test</button><span class="small ${doubles?'err':'muted'}">${tests.length} test${tests.length===1?'':'s'} · ${doubles} double booking${doubles===1?'':'s'}</span></div>
    ${tests.length?`<div class="tablewrap"><table><tr><th>Time</th><th>Slot</th><th>A</th><th>B</th></tr>${tests.slice(0,4).map(x=>`<tr><td class="num">${x.t}</td><td>${x.slot}</td><td>${x.a}</td><td>${x.b.split(' ·')[0]}</td></tr>`).join('')}</table></div>`:''}
    <h3>Check-in tablet</h3><p class="small muted">Types a sample patient's last 4 digits on the tablet.</p><div class="actions">${[['0142','Priya Raman'],['7788','Lucie Fortin'],['4410','Jordan Tremblay']].map(([d,n])=>`<button class="btn sm" onclick="demoKiosk('${d}')">${d} · ${n}</button>`).join('')}</div>
    <h3>Scheduled jobs</h3><div class="actions"><button class="btn sm" onclick="runReminderJob()">Run the 9:00 am reminder job now</button></div>
    <h3>Setup wizard</h3><div class="actions"><button class="btn sm" onclick="setupRestart();surface('web',$$('.switch button')[2]);wgo('setup')" ${state.webUser&&webUser().role==='admin'?'':'disabled'}>Restart the timed setup test</button></div>${state.webUser&&webUser().role==='admin'?'':'<p class="small muted">Sign in to the website as an admin first.</p>'}
    ${state.demoMsg?`<p class="small" role="status">${esc(state.demoMsg)}</p>`:''}`;
}

// ---------- live ticker: queue freshness, lock countdowns, setup timer. It only ever changes text. ----------
state.kiosk={step:'enter',digits:'',lang:'en'};
setInterval(()=>{
  const ago=Math.round((Date.now()-state.lastChange)/1000),txt=`Live · updated ${ago<2?'just now':ago+' s ago'}`;
  const sl=$('#s-live'),wl=$('#w-live');if(sl)sl.textContent=txt;if(wl)wl.textContent=txt;
  let expired=false;for(const k in state.locks)if(state.locks[k].until<=Date.now()){delete state.locks[k];expired=true}
  // a patient whose hold ran out mid-booking goes back to choose a time; they can never book a slot they no longer hold
  if(expired&&state.booking.time&&!holdOk()&&['book2','book3','otp'].includes(cur.patient))backToTimes();
  if(expired&&state.manual&&state.manual.time&&!lockAt(state.manual.clin,state.manual.time)){state.manual.time=null;state.manual.err='Your 2-minute hold ran out. Pick the time again.'}
  if(expired)renderAll();
  updateLocks();
  const st=$('#w-setup-timer');if(st&&state.webUser)st.textContent=state.setup.finished?`Finished in ${elapsed()}`:`Setup time ${elapsed()}`;
},1000);
document.addEventListener('keydown',e=>{
  if(e.key==='Escape'&&!$('#p-sheet').hidden){closeSheet();return}
  if(e.key==='Escape'&&!$('#demo').hidden){toggleDemo();return}
  // the check-in tablet also takes a keyboard: digits, Backspace, Enter
  const tag=document.activeElement?.tagName||'';
  if(cur.surface==='web'&&cur.web==='kiosk'&&state.webUser&&state.kiosk.step==='enter'&&!/INPUT|SELECT|TEXTAREA/.test(tag)){
    if(/^\d$/.test(e.key)){kioskKey(e.key);e.preventDefault()}
    else if(e.key==='Backspace'){kioskKey('del');e.preventDefault()}
    else if(e.key==='Enter'&&tag!=='BUTTON'){kioskFind();e.preventDefault()}
  }
});
// OTP boxes: move to the next box as you type, back on delete
$$('#p-otp input').forEach((inp,i,all)=>{inp.addEventListener('input',()=>{inp.value=digits(inp.value).slice(-1);if(inp.value&&all[i+1])all[i+1].focus()});inp.addEventListener('keydown',e=>{if(e.key==='Backspace'&&!inp.value&&all[i-1])all[i-1].focus()});inp.addEventListener('paste',e=>{const t=digits(e.clipboardData.getData('text'));if(t.length===6){e.preventDefault();[...t].forEach((d,j)=>all[j].value=d)}})});

function renderAll(){renderPatient();renderStaff();renderWeb();renderDemo()}
// every redraw keeps keyboard focus and the caret where the person left them
for(const name of ['renderPatient','renderStaff','renderWeb','renderDemo']){const f=window[name];window[name]=(...a)=>keepFocus(()=>f(...a))}
// the collapsed sidebar shows icons only; give each a tooltip as well as its hidden text label
$$('.side button').forEach(b=>{b.title=b.textContent.trim()});
$('#hint').textContent=hints.patient;
renderAll();
syncThemeButton();
openFromHash();
