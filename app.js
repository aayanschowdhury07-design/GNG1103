'use strict';
// ClinicFlow prototype. The patient app, staff app and staff website all read and write this one in-page
// data set, which stands in for the shared backend/API. Nothing leaves the browser: no real texts, emails or logins.

// ---------- helpers ----------
const $=(s,r=document)=>r.querySelector(s), $$=(s,r=document)=>[...r.querySelectorAll(s)];
const esc=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
const ic=(id,cls='ic')=>`<svg class="${cls}" aria-hidden="true"><use href="#i-${id}"/></svg>`;
const digits=s=>String(s||'').replace(/\D/g,'');
function toast(which,msg){const el=$('#'+which+'-toast');el.textContent=msg;el.classList.add('show');clearTimeout(el._t);el._t=setTimeout(()=>el.classList.remove('show'),2600)}
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

// ---------- shared data (the "database") ----------
const ROLES={admin:'Admin',frontdesk:'Front desk',clinician:'Clinician',support:'Support'};
const PATIENT='Priya Raman (patient)', SYSTEM='System';
const state={
  clins:[
    {id:'osei',name:'Dr. Kwame Osei',short:'Dr. Osei',role:'Physiotherapist',hours:'Mon–Fri 9–5'},
    {id:'lam',name:'Mei Lam, PT',short:'M. Lam',role:'Physiotherapist',hours:'Tue, Thu, Sat 9–2'},
    {id:'daoud',name:'Dr. Rania Daoud',short:'Dr. Daoud',role:'Chiropractor',hours:'Thu only',visiting:true},
    {id:'walk',name:'Walk-in room',short:'Walk-in',role:'Same-day visits',hours:'Mon–Fri 9–5',room:true},
  ],
  services:[
    {name:'Physiotherapy · follow-up',short:'Physio follow-up',dur:30,buf:0,online:true,who:'Returning patients',form:'Reason',clins:['osei','lam']},
    {name:'Physiotherapy · initial assessment',short:'Initial assessment',dur:45,buf:5,online:true,who:'New and returning',form:'Contact, consent, reason',clins:['osei','lam']},
    {name:'Chiropractic · adjustment',short:'Chiro adjustment',dur:20,buf:5,online:true,who:'New and returning',form:'Contact, consent',clins:['daoud']},
    {name:'Walk-in · same day',short:'Walk-in',dur:15,buf:0,online:false,who:'Front desk only',form:'Contact',clins:['walk']},
  ],
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
    {t:'Freed 10:30 slot (Dr. Osei) offered to Jordan Tremblay 2 min 10 s after the cancellation.',s:'09:30',k:'warn'},
    {t:'Omar Haddad cancelled 10:30 with Dr. Osei.',s:'09:28',k:'warn'},
    {t:'Marcus Chen is late for 9:30 and not checked in.',s:'09:42',k:'crit'},
    {t:'Intake nudges sent to 5 patients; 2 fell back to text.',s:'08:30',k:'info'},
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
    {t:'Mon 09:00',to:'Priya Raman',msg:'Reminder, 24 h',ch:'Push → text',out:'Push not opened in 30 min; text delivered'},
    {t:'Mon 09:00',to:'Lucie Fortin',msg:'Reminder, 24 h',ch:'Push',out:'Delivered · confirmed'},
    {t:'Sun 09:00',to:'Priya Raman',msg:'Reminder, 48 h',ch:'Push → email',out:'Delivered'},
    {t:'Sun 09:00',to:'Raj Singh',msg:'Reminder, 48 h',ch:'Push → email',out:'Email delivered · no reply'},
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
const STATUS={booked:['mute','Booked'],confirmed:['info','Confirmed'],checked:['good','Checked in'],waiting:['warn','Waiting'],invisit:['info','In visit'],done:['good','Complete'],late:['crit','Late'],noshow:['crit','No-show'],cancelled:['mute','Cancelled']};
const ACTIVE=q=>!['cancelled','noshow'].includes(q.status);
const clinById=id=>state.clins.find(c=>c.id===id)||{name:id,short:id};
const svcByName=n=>state.services.find(s=>s.name===n)||state.services[0];
const pill=st=>{const [k,l]=STATUS[st]||['mute',st];return `<span class="pill ${k}">${l}</span>`};
const touch=()=>{state.lastChange=Date.now()};

// ---------- audit log: every change goes through here ----------
function logAudit(actor,action,record,detail){state.audit.unshift({t:clock(),actor,action,record,detail});touch()}
const userById=id=>state.users.find(u=>u.id===id);
const staffUser=()=>userById(state.staffUser), webUser=()=>userById(state.webUser);
const actorOf=u=>u?`${u.name} (${ROLES[u.role]})`:'Signed-out user';
function alertStaff(t,k='info'){state.sAlerts.unshift({t,s:clock(false),k})}
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
function showScreen(root,id){$$('.screen',root).forEach(s=>s.classList.toggle('active',s.dataset.s===id));$$('.tabbar button',root.parentElement).forEach(b=>b.setAttribute('aria-selected',b.dataset.tab===(TAB_OF[id]||id)));const a=$('.screen.active',root);if(a)a.scrollTop=0}
const NEEDS_SIGNIN=['home','appt','notifs','profile','history','family','checkin','intake','waitlist','offer'];
function pgo(id){if(!state.pSigned&&NEEDS_SIGNIN.includes(id))id='signin';showScreen($('#p-screens'),id);cur.patient=id;syncHash();renderPatient()}
function sgo(id){if(!state.staffUser)id='login';else if(!staffTabs().includes(id)&&!['patient'].includes(id))id='queue';showScreen($('#s-screens'),id);cur.staff=id;syncHash();renderStaff()}
function wgo(id,btn){if(!state.webUser){cur.web=id;renderWeb();return}if(!webPages().includes(id))id=webPages()[0];$$('.page').forEach(p=>p.classList.toggle('active',p.dataset.p===id));$$('.side button').forEach(b=>b.setAttribute('aria-selected',b.dataset.p===id));cur.web=id;syncHash();renderWeb()}
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
function smsBanner(text){const el=$('#p-sms');el.innerHTML=`<b>Messages · now</b><span>${esc(text)}</span>`;el.hidden=false;clearTimeout(el._t);el._t=setTimeout(()=>el.hidden=true,7000)}

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
  if(!acquireLock(s.clin,t,'patient',300)){showErr('p-slot-err','Someone at the front desk is booking that time right now. Pick another time.');return}
  state.booking.time=t;state.booking.lockedClin=s.clin;showErr('p-slot-err');renderAll();
}
function book2Next(){
  const b=state.booking;
  if(!b.time||!lockAt(b.lockedClin,b.time)){showErr('p-slot-err',b.time?'Your hold on that time ran out. Pick a time again.':'Choose a time to continue.');b.time=null;renderPatient();return}
  if(b.mode==='resched')return confirmReschedule();
  pgo('book3');
}
function sendCode(){
  const name=$('#p-name').value.trim(),ph=digits($('#p-phone').value);
  if(!name)return showErr('p-details-err','Enter your full name.');
  if(ph.length<10)return showErr('p-details-err','Enter a mobile number with area code, for example 416 555 0142.');
  if(!$('#p-c2').checked)return showErr('p-details-err','Please agree to the cancellation policy to book.');
  const pend=state.otp.pending[ph]||0;
  if(pend>=2){logAudit('Guest '+ph.slice(-4),'booking.rate_limited','PHONE …'+ph.slice(-4),`Blocked: ${pend} unconfirmed bookings today (limit 2)`);return showErr('p-details-err','This number already has 2 unconfirmed bookings today. Confirm one with its code, or call the clinic at 416 555 0100.')}
  showErr('p-details-err');state.otp.pending[ph]=pend+1;state.otp.code=newCode();state.otp.phone=ph;
  $('#p-otp-to').textContent=`We texted a 6-digit code to ${$('#p-phone').value.trim()}. It expires in 10 minutes.`;
  $$('#p-otp input').forEach(i=>i.value='');showErr('p-otp-err');
  pgo('otp');smsBanner(`ClinicFlow: ${state.otp.code} is your Maple Grove Clinic code. Don't share it.`);
  setTimeout(()=>$('#p-otp input')?.focus(),50);
}
function resendCode(){state.otp.code=newCode();smsBanner(`ClinicFlow: ${state.otp.code} is your new Maple Grove Clinic code.`);toast('p','New code sent')}
function fillCode(){if(!state.otp.code)return;[...state.otp.code].forEach((d,i)=>$$('#p-otp input')[i].value=d)}
function confirmBooking(){
  const code=$$('#p-otp input').map(i=>i.value).join('');
  if(code.length<6)return showErr('p-otp-err','Enter all 6 digits of the code.');
  if(code!==state.otp.code)return showErr('p-otp-err',"That code doesn't match. Check the text message and try again.");
  const b=state.booking,who=whoName(),svc=svcByName(b.service);
  const entry={name:who,clin:b.lockedClin,time:b.time,svc:svc.short,svcFull:svc.name,status:'booked',forms:false,phone:state.otp.phone.slice(-4),mine:true,guardian:who!=='Priya Raman'};
  if(!commitBooking(entry,'patient')){b.time=null;showErr('p-slot-err','Someone booked that time a moment ago. Pick another time.');pgo('book2');return}
  state.otp.pending[state.otp.phone]=Math.max(0,(state.otp.pending[state.otp.phone]||1)-1);state.otp.code=null;
  if($('#p-c1').checked&&!state.consent.sms){state.consent={sms:true,at:'Sep 29, 2026'};logAudit(PATIENT,'consent.sms.granted','PAT-0142','Text reminders consent captured at booking')}
  state.pSigned=true;
  logAudit(entry.guardian?'Priya Raman (guardian)':PATIENT,'appointment.create','APT-'+(20900+entry.id),`${svc.short} · ${clinById(entry.clin).short} · Tue ${ampm(entry.time)} · phone verified · guest link`);
  notifyPatient(`Booked${entry.guardian?' for '+who.split(' ')[0]:''}: ${svc.short}, Tue Sep 29, ${ampm(entry.time)} with ${clinById(entry.clin).short}.`,'text and email','good');
  alertStaff(`New online booking: ${who}, ${ampm(entry.time)} with ${clinById(entry.clin).short} (${entry.guardian?'booked by guardian Priya Raman':'guest'}, phone verified).`,'info');
  deliver(who,'Booking confirmation','Push → text → email','Delivered');
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
function cancelAppt(){
  const q=me();if(!q)return;q.status='cancelled';releaseLocks('patient');
  logAudit(PATIENT,'appointment.cancel','APT-'+(20900+q.id),`${q.svc} · ${ampm(q.time)} · cancelled in app`);
  notifyPatient(`Your ${ampm(q.time)} visit is cancelled. The slot was offered to the waitlist.`,'push','mute');
  freeSlot(q.clin,q.time,`${q.name} cancelled`);
  toast('p','Visit cancelled. The slot is offered to the waitlist.');pgo('home');
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
  if(!q.ticket)q.ticket='A-'+(state.nextTicket++);q.status='checked';q.checkedAt=clock(false);
  logAudit(actor,'appointment.checkin','APT-'+(20900+q.id),`Checked in via ${via} · ticket ${q.ticket}`);
  alertStaff(`${q.name} checked in (${via}). Ticket ${q.ticket}.`,'good');touch();
}
function checkIn(){const q=me();if(!q)return;checkInEntry(q,'phone, 140 m from the clinic',PATIENT);toast('p',`Checked in. Ticket ${q.ticket}.`);renderAll()}
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

function renderPatient(){
  const q=me(),b=state.booking;
  // home
  const reasonDone=q&&q.forms;
  $('#p-todo-count').textContent=reasonDone?'0 left':'1 left';$('#p-todo-count').className=`pill ${reasonDone?'good':'warn'}`;
  $('#p-reason-todo').innerHTML=reasonDone?'<span class="pill good">Done</span><div class="grow"><div class="t">Reason for visit</div><div class="s">Submitted</div></div>':'<span class="pill warn">Open</span><div class="grow"><div class="t">Reason for visit</div><div class="s">2 min · needed before your visit</div></div><button class="btn sm" onclick="pgo(\'intake\')">Fill</button>';
  $('#p-consent-line').textContent=state.consent.sms?`Text reminders on since ${state.consent.at}`:'Text reminders off · push and email only';
  $('#p-notice').textContent=state.notice;
  $('#p-near-count').textContent=`${state.directory.filter(c=>c.accepting).length} clinics`;
  const h=$('#p-hero');
  if(!q||q.status==='cancelled'||q.status==='noshow')h.innerHTML=`<p class="eyebrow">No upcoming visit</p><h3>Book when you're ready</h3><div class="row"><button class="btn" onclick="startBooking()">Book a visit</button></div>`;
  else if(q.status==='checked'||q.status==='waiting'){const ahead=queueAhead(q);h.innerHTML=`<p class="eyebrow">You're checked in · ticket ${q.ticket}</p><h3>${q.status==='checked'?'The front desk is adding you to the queue':ahead?`${ahead} ${ahead===1?'person':'people'} ahead of you`:'You are next'}</h3><p style="margin-bottom:10px;opacity:.9">Estimated wait about ${Math.max(3,ahead*5+3)} minutes. We'll send a push when it's your turn.</p><div class="row"><button class="btn" onclick="pgo('checkin')">See queue</button></div>`}
  else if(q.status==='invisit')h.innerHTML=`<p class="eyebrow">Now</p><h3>${clinById(q.clin).short} is ready for you</h3><p style="opacity:.9">Room 2, down the hall on the left.</p>`;
  else if(q.status==='done')h.innerHTML=`<p class="eyebrow">Visit complete</p><h3>Thanks, Priya</h3><p style="margin-bottom:10px;opacity:.9">Book your next follow-up while it's fresh.</p><div class="row"><button class="btn" onclick="startBooking()">Book follow-up</button></div>`;
  else h.innerHTML=`<p class="eyebrow">Next visit · Tue Sep 29 · ${q.status==='confirmed'?'confirmed':'please confirm'}</p><h3>${ampm(q.time)} · ${esc(q.svcFull||q.svc)}</h3><p style="margin-bottom:10px;opacity:.9">${clinById(q.clin).name} · Maple Grove Clinic${forLabel(q.name)}</p><div class="row"><button class="btn" onclick="pgo('appt')">Manage</button>${q.status==='booked'?'<button class="btn" onclick="confirmVisit()">Confirm</button>':'<button class="btn" onclick="pgo(\'checkin\')">Check in</button>'}</div>`;
  // directory
  const term=($('#p-find')?.value||'').toLowerCase().trim();
  const list=state.directory.filter(c=>(!term||(c.name+' '+c.services).toLowerCase().includes(term.replace(/therapy$/,'')))&&(state.findFilter==='all'||(state.findFilter==='accepting'?c.accepting:c.today)));
  $$('#p-find-filter button').forEach(x=>x.setAttribute('aria-pressed',x.getAttribute('onclick').includes(`'${state.findFilter}'`)));
  $('#p-clinics').innerHTML=list.length?list.map((c,i)=>`<div class="item"><div class="avatar">${c.ini}</div><div class="grow"><div class="t">${c.name}</div><div class="s">${c.dist} km · ${c.services} · ${c.next}</div></div>${c.self?'<button class="btn sm primary" onclick="startBooking()">Book</button>':c.accepting?`<button class="btn sm" onclick="toast('p','Opens ${c.name}&#39;s booking page')">Book</button>`:`<button class="btn sm" onclick="toast('p','Added to ${c.name}&#39;s waitlist')">Join list</button>`}</div>`).join(''):'<div class="item"><div class="s">No clinics match. Try "physio" or switch the filter to All.</div></div>';
  // booking
  $('#p-who').innerHTML=[['me','Me'],...state.family.map(f=>[f.id,f.name.split(' ')[0]])].map(([id,l])=>`<button aria-pressed="${b.who===id}" onclick="state.booking.who='${id}';renderPatient()">${esc(l)}</button>`).join('')+`<button aria-pressed="false" onclick="state.famFrom='book';pgo('family')">+ Add</button>`;
  $('#p-services').innerHTML=state.services.filter(s=>s.online).map(s=>`<button class="choice" aria-pressed="${b.service===s.name}" onclick="pickService(this.dataset.n)" data-n="${esc(s.name)}"><div class="grow"><div class="t">${esc(s.name)}</div><div class="s small muted">${s.dur} min · ${s.who}</div></div></button>`).join('');
  const svc=svcByName(b.service),res=b.mode==='resched';
  $('#p-book2-title').textContent=res?'Pick a new time':'Who and when';$('#p-book2-steps').hidden=res;$('#p-clin-label').textContent=res?'Clinician':'Step 2 of 4 · Clinician';
  $('#p-book2-next').textContent=res?'Move my visit':'Continue';
  const clinOpts=svc.clins.map(id=>clinById(id)).concat(svc.clins.length>1?[{id:'any',name:'First available',role:'Any clinician'}]:[]);
  $('#p-clin').innerHTML=clinOpts.map(c=>`<button class="choice" aria-pressed="${b.clin===c.id}" onclick="pickClin('${c.id}')"><div class="avatar">${c.id==='any'?'·':initials(c.name)}</div><div class="grow"><div class="t">${esc(c.name)}</div><div class="small muted">${esc(c.role)}${c.id!=='any'&&capacity(c.id)===0?' · not in on Tuesdays':''}</div></div></button>`).join('');
  const lab={taken:'taken',blocked:'unavailable',held:'being booked by someone else'};
  $('#p-slots').innerHTML=TIMES.map(t=>{const s=patientSlot(t),sel=b.time===t;const dis=!s.clin&&!sel;return `<button aria-pressed="${sel}" class="${s.state==='freed'?'freed':''}" ${dis?'disabled':''} aria-label="${ampm(t)}${dis?', '+lab[s.state]:''}" onclick="selectSlot('${t}')">${t}</button>`}).join('');
  const lk=b.time&&lockAt(b.lockedClin,b.time);
  $('#p-lock').hidden=!lk;if(lk){const left=Math.max(0,Math.round((lk.until-Date.now())/1000));$('#p-lock').innerHTML=`${ic('lock')} ${ampm(b.time)} with ${clinById(b.lockedClin).short} is held for you for ${Math.floor(left/60)}:${String(left%60).padStart(2,'0')}`}
  $('#p-slot-note').textContent=capacity(b.clin==='any'?svc.clins[0]:b.clin)===0?'This clinician is not in on Tuesdays. Join the waitlist to hear about other days.':'Dashed times were freed by a cancellation. Greyed-out times are taken or unavailable.';
  const sum=`<b>${esc(b.service)}</b><br>For ${esc(whoName())}<br>${b.lockedClin&&b.time?clinById(b.lockedClin).name:clinById(b.clin).name}<br>Tue Sep 29 · ${b.time?ampm(b.time):'time not chosen'}<br>Maple Grove Clinic, 214 Elm Ave`;
  $('#p-summary').innerHTML=sum;
  const lb=state.queue.find(x=>x.id===state.lastBooked);
  $('#p-summary2').innerHTML=lb?`<b>${esc(lb.svcFull)}</b><br>For ${esc(lb.name)}<br>${clinById(lb.clin).name}<br>Tue Sep 29 · ${ampm(lb.time)}<br>Maple Grove Clinic, 214 Elm Ave`:'';
  $('#p-confirmed-title').textContent=lb&&lb.guardian?`${lb.name.split(' ')[0]} is booked`:"You're booked";
  // your visit
  if(q){
    $('#p-apptcard').innerHTML=`<div class="row between"><p class="eyebrow">Tue Sep 29</p>${pill(q.status)}</div><h3 style="font-size:20px;margin:4px 0">${ampm(q.time)} · ${esc(q.svcFull||q.svc)}</h3><p class="small muted">${clinById(q.clin).name} · Maple Grove Clinic · 214 Elm Ave${forLabel(q.name)}</p><div class="row" style="margin-top:10px"><span class="pill ${q.forms?'good':'warn'}">Forms ${q.forms?'done':'1 open'}</span><span class="pill mute">Ref APT-${20900+q.id}</span></div>`;
    const stages=[['booked','Booked'],['confirmed','Confirmed'],['checked','Checked in'],['waiting','Waiting'],['done','Complete']];
    const pos={booked:0,late:0,confirmed:1,checked:2,waiting:3,invisit:3,done:5}[q.status];
    $('#p-tracker').innerHTML=pos===undefined?`<li class="now">This visit was ${q.status==='noshow'?'missed':'cancelled'}.</li>`:stages.map(([k,l],i)=>`<li class="${i<pos?'done':i===pos?'now':''}"><i>${i<pos?ic('check'):i+1}</i><span>${l}${k==='waiting'&&q.status==='invisit'?' · now in your visit':''}${i===pos&&k==='booked'?' · please confirm':''}</span></li>`).join('');
    const live=!['cancelled','noshow','done'].includes(q.status),early=['booked','confirmed','late'].includes(q.status);
    $('#p-appt-actions').innerHTML=!live?'<button class="btn primary block" onclick="startBooking()">Book again</button>':(q.status==='booked'?'<button class="btn primary block" onclick="confirmVisit()">Confirm I\'m coming</button>':'')+(early?'<button class="btn block" onclick="startReschedule()">Reschedule</button><button class="btn block" onclick="pgo(\'waitlist\')">Ask for a different time</button><button class="btn danger block" onclick="cancelAppt()">Cancel visit</button>':'');
    $('#p-policy').textContent=`Free cancellation until ${state.rules.cancelWindow} hours before your visit. After that the clinic may record a late cancellation.`;
  }
  // waitlist preferences
  const p=state.wlPrefs,chip=(kind,v,l)=>`<button aria-pressed="${p[kind].includes(v)}" onclick="toggleChip('${kind}','${v}')">${l}</button>`;
  $('#p-wl-prefs').innerHTML=`<p class="eyebrow">Days</p><div class="slots">${['Mon','Tue','Wed','Thu','Fri','Sat'].map(d=>chip('days',d,d)).join('')}</div><p class="eyebrow">Times</p><div class="slots">${chip('times','morning','Morning')}${chip('times','afternoon','Afternoon')}${chip('times','after4','After 4 pm')}</div><p class="eyebrow">Clinician</p><div class="seg"><button aria-pressed="${p.clin==='any'}" onclick="state.wlPrefs.clin='any';renderPatient()">Any</button><button aria-pressed="${p.clin==='osei'}" onclick="state.wlPrefs.clin='osei';renderPatient()">Dr. Osei only</button></div>`;
  const of=state.freed.find(x=>x.id===state.pendingOffer);
  $('#p-offer-hero').innerHTML=of?`<p class="eyebrow">Waitlist offer · held for you for ${state.rules.hold} minutes</p><h3>Tue Sep 29, ${ampm(of.time)}</h3><p style="opacity:.9">Physiotherapy · ${clinById(of.clin).name} · Maple Grove Clinic</p>`:'<h3>This offer has ended</h3>';
  // check-in
  const c=$('#p-checkin');
  if(!q||!['booked','confirmed','late','checked','waiting','invisit','done'].includes(q.status))c.innerHTML='<div class="card"><p class="small muted">No visit to check in for today.</p></div>';
  else if(['booked','confirmed','late'].includes(q.status))c.innerHTML=`<div class="card stack"><p class="eyebrow">Tue Sep 29 · ${ampm(q.time)} · ${clinById(q.clin).short}</p><p>You're 140 m from Maple Grove Clinic. Check-in is open.</p>${q.forms?'':'<div class="banner">One form is still open. You can check in now and finish it while you wait.</div>'}<button class="btn primary block" onclick="checkIn()">I'm here</button><p class="small muted" style="text-align:center">No phone signal? On the front-desk tablet, enter the last 4 digits of your phone: <b class="num">${q.phone||'0142'}</b></p></div>`;
  else if(q.status==='checked'||q.status==='waiting'){const ahead=queueAhead(q);c.innerHTML=`<div class="card" style="text-align:center"><p class="eyebrow">Ticket ${q.ticket}</p><div class="queue-ring"><div><b>${q.status==='checked'?'·':ahead}</b><span class="small muted">${q.status==='checked'?'joining the queue':'ahead of you'}</span></div></div><h3 style="font-size:18px">About ${Math.max(3,ahead*5+3)} minutes</h3><p class="small muted" style="margin-top:4px">Feel free to step out; we'll send a push when you're next.</p></div><div class="card list"><div class="item"><span class="pill good">Checked in</span><div class="grow"><div class="t">${q.checkedAt||''}</div><div class="s">Front desk notified</div></div></div>${q.forms?'':'<div class="item"><span class="pill warn">Open</span><div class="grow"><div class="t">Reason for visit</div><div class="s">Finish while you wait</div></div><button class="btn sm" onclick="pgo(\'intake\')">Fill</button></div>'}<div class="item"><span class="pill mute">Now</span><div class="grow"><div class="t">Serving ${nowServing()||'—'}</div><div class="s">The waiting-room board shows ticket numbers only</div></div></div></div>`}
  else if(q.status==='invisit')c.innerHTML=`<div class="hero info"><p class="eyebrow">Now</p><h3>Please go to Room 2</h3><p style="opacity:.9">${clinById(q.clin).name} · down the hall on the left</p></div>`;
  else c.innerHTML=`<div class="card" style="text-align:center"><div class="avatar big-check">${ic('check')}</div><h3>Visit complete</h3><p class="small muted">Book your next follow-up from Home.</p></div>`;
  // family, history, notifications, profile
  $('#p-family').innerHTML=state.family.length?state.family.map(f=>`<div class="item"><div class="avatar">${initials(f.name)}</div><div class="grow"><div class="t">${esc(f.name)}</div><div class="s">${esc(f.rel)} · born ${niceDate(f.dob)}</div></div><button class="btn sm" onclick="startBooking();state.booking.who='${f.id}';renderPatient()">Book</button></div>`).join(''):'<div class="item"><div class="s">No one added yet.</div></div>';
  const owing=state.history.reduce((t,v)=>t+v.owing,0);
  $('#p-balance').innerHTML=`<div class="row between"><div><p class="eyebrow">Balance owing</p><b class="figure">$${owing.toFixed(2)}</b></div>${owing?'<button class="btn sm primary" onclick="payBalance()">Pay now</button>':'<span class="pill good">All paid</span>'}</div>`;
  $('#p-history').innerHTML=state.history.map(v=>`<div class="item"><span class="pill ${v.owing?'warn':'good'}">${v.owing?'$'+v.owing+' owing':'Paid'}</span><div class="grow"><div class="t">${v.svc}</div><div class="s">${v.date} · ${v.clin} · ${v.clinic}${forLabel(v.who)}</div></div><button class="btn sm" onclick="toast('p','Receipt for ${v.date} emailed')">Receipt</button></div>`).join('');
  $('#p-notifs').innerHTML=state.pNotifs.map(n=>{let act='';if(n.act==='confirm'&&q&&q.status==='booked')act='<div class="actions"><button class="btn sm primary" onclick="confirmVisit()">Confirm</button><button class="btn sm" onclick="startReschedule()">Reschedule</button></div>';else if(n.act==='intake'&&q&&!q.forms)act='<div class="actions"><button class="btn sm" onclick="pgo(\'intake\')">Fill the form</button></div>';else if(n.act==='offer'&&state.pendingOffer)act='<div class="actions"><button class="btn sm primary" onclick="pgo(\'offer\')">See offer</button></div>';return `<div class="item"><span class="pill ${n.k}" style="width:8px;height:8px;padding:0;border-radius:50%"></span><div class="grow"><div class="t">${esc(n.t)}</div><div class="s">${esc(n.s)}</div>${act}</div></div>`}).join('');
  $('#p-sms-consent').textContent=state.consent.sms?`On · consent given ${state.consent.at}`:`Off · withdrawn ${state.consent.at}`;
  $('#p-sms-toggle').textContent=state.consent.sms?'Turn off':'Turn on';
  $('#p-large-toggle').textContent=state.largeText?'Turn off':'Turn on';
}
function queueAhead(q){const w=state.queue.filter(x=>x.status==='waiting'&&x.clin===q.clin&&(x.ticket||'')<(q.ticket||''));return q.status==='checked'?w.length:w.length}
function nowServing(){const v=state.queue.filter(q=>q.status==='invisit').map(q=>q.ticket).filter(Boolean);return v.join(', ')}

// ---------- staff app ----------
function staffTabs(){const u=staffUser();if(!u)return['login'];return {admin:['queue','schedule','waitlist','alerts','me'],frontdesk:['queue','schedule','waitlist','alerts','me'],clinician:['queue','schedule','alerts','me'],support:['queue','alerts','me']}[u.role]}
function canAct(q){const u=staffUser();if(!u||u.role==='support')return false;return u.role!=='clinician'||q.clin===u.clin}
function setStatus(id,st){
  const q=state.queue.find(x=>x.id===id),prev=q.status,u=staffUser();if(!canAct(q))return toast('s','Your role can view this but not change it');
  if(st==='checked'){checkInEntry(q,'front desk',actorOf(u))}
  else{q.status=st;if(st==='waiting'){q.waitStart=Date.now();q.since=0}logAudit(actorOf(u),'appointment.status','APT-'+(20900+q.id),`${STATUS[prev][1]} → ${STATUS[st][1]}`)}
  if(q.mine&&st==='invisit')notifyPatient(`${clinById(q.clin).short} is ready. Please go to Room 2.`,'push','info');
  if(st==='noshow'){alertStaff(`${q.name} marked no-show for ${ampm(q.time)}. Listed in Missed visits.`,'crit');state.missed.unshift({id:Date.now(),date:'Today',time:ampm(q.time),name:q.name,clin:clinById(q.clin).short,svc:q.svc,reminder:prev==='booked'?'Delivered, no reply':'Confirmed by text',prior:0,status:'open'})}
  touch();toast('s',{checked:'Checked in',waiting:'Added to the queue',invisit:'Called in',done:'Visit complete',noshow:'Marked no-show'}[st]||'Updated');renderAll();
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
  const late=list.filter(q=>q.status==='late');const bn=$('#s-banner');bn.hidden=!late.length;bn.textContent=late.length?`${late[0].name} is late and not checked in. Text them or mark a no-show.`:'';
  $('#s-walkin').hidden=!['admin','frontdesk'].includes(u.role);
  const order={invisit:0,waiting:1,checked:2,late:3,confirmed:4,booked:5,done:6};
  $('#s-queue').innerHTML=list.sort((a,b)=>order[a.status]-order[b.status]||tIdx(a.time)-tIdx(b.time)).map(q=>{
    let act='';const can=canAct(q);
    if(can){if(q.status==='checked')act=`<button class="btn sm primary" onclick="setStatus(${q.id},'waiting')">Add to queue</button>`;
      else if(q.status==='waiting')act=`<button class="btn sm primary" onclick="setStatus(${q.id},'invisit')">Call in</button>`;
      else if(q.status==='invisit')act=`<button class="btn sm primary" onclick="setStatus(${q.id},'done')">Complete</button>`;
      else if(q.status==='late')act=`<button class="btn sm primary" onclick="setStatus(${q.id},'checked')">Arrived</button><button class="btn sm" onclick="textPatient(${q.id})">Text</button><button class="btn sm danger" onclick="setStatus(${q.id},'noshow')">No-show</button>`;
      else if(q.status!=='done')act=`<button class="btn sm primary" onclick="setStatus(${q.id},'checked')">Arrived</button>${q.status==='booked'?`<button class="btn sm" onclick="remindPatient(${q.id})">Remind</button>`:''}${q.forms?'':`<button class="btn sm" onclick="sendForm(${q.id})">Send form</button>`}`}
    const sub=q.status==='waiting'?`waiting ${waitMins(q)} min · ticket ${q.ticket}`:q.status==='invisit'?`in room · ticket ${q.ticket}`:q.status==='checked'?`arrived ${q.checkedAt} · ticket ${q.ticket}`:q.forms?'forms complete':'form missing';
    return `<div class="qcard"><div class="row between"><div class="row"><div class="avatar">${initials(q.name)}</div><div><div class="t">${esc(q.name)}</div><div class="small muted">${ampm(q.time)} · ${esc(q.svc)} · ${clinById(q.clin).short}</div></div></div>${pill(q.status)}</div><div class="row between"><span class="wait">${sub}</span><button class="btn sm ghost" onclick="state.selectedPatient=${q.id};sgo('patient')">Details</button></div>${act?`<div class="actions">${act}</div>`:''}</div>`}).join('')||'<p class="small muted">No patients for this filter.</p>';
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
  $('#s-alerts').innerHTML=state.sAlerts.slice(0,30).map(n=>`<div class="item"><span class="pill ${n.k}" style="width:8px;height:8px;padding:0;border-radius:50%"></span><div class="grow"><div class="t">${esc(n.t)}</div><div class="s">${n.s}</div></div></div>`).join('');
  // account
  $('#s-me-ini').textContent=initials(u.name);$('#s-me-name').textContent=u.name;$('#s-me-role').textContent=`${ROLES[u.role]} · Maple Grove Clinic`;
  $('#s-me-perms').innerHTML=({admin:['Everything, including roles and settings'],frontdesk:['Check patients in, queue and complete visits','Book, text and send forms','Answer waitlist offers'],clinician:['See and update your own patients only','Your own schedule'],support:['View the queue (read-only)','See alerts']}[u.role]).map(x=>`<li>${x}</li>`).join('');
}
function textPatient(id){const q=state.queue.find(x=>x.id===id),u=staffUser();deliver(q.name,'Quick text','Text','Delivered');logAudit(actorOf(u),'notification.sent','APT-'+(20900+q.id),'Quick text from staff app');toast('s',`Text sent to ${q.name.split(' ')[0]}`);renderAll()}
function remindPatient(id){const q=state.queue.find(x=>x.id===id),u=staffUser()||webUser();deliver(q.name,'Reminder (manual)','Push → text','Delivered');logAudit(actorOf(u),'notification.sent','APT-'+(20900+q.id),'Manual reminder with one-tap confirm');toast(cur.surface==='web'?'w':'s',`Reminder sent to ${q.name.split(' ')[0]}`);renderAll()}
function sendForm(id){const q=state.queue.find(x=>x.id===id),u=staffUser()||webUser();deliver(q.name,'Intake form link','Push → text','Delivered');logAudit(actorOf(u),'notification.sent','APT-'+(20900+q.id),'Reason-for-visit form link');if(q.mine)notifyPatient('Please complete your reason-for-visit form before your visit.','text','warn','intake');toast(cur.surface==='web'?'w':'s',`Form link sent to ${q.name.split(' ')[0]}`);renderAll()}
function holdSlot(fid){const f=state.freed.find(x=>x.id===fid),u=staffUser();f.status='held';f.offers.filter(o=>o.status==='holding').forEach(o=>o.status='withdrawn');logAudit(actorOf(u),'slot.hold','SLOT '+f.clin+' '+f.time,'Held for a phone booking');toast('s','Slot held for a phone booking');touch();renderAll()}

// ---------- staff website ----------
const PAGES={admin:['dash','cal','queue','kiosk','wait','missed','services','notif','users','audit','reports','setup'],frontdesk:['dash','cal','queue','kiosk','wait','missed','reports'],clinician:['dash','cal','queue','reports'],support:['queue']};
function webPages(){const u=webUser();return u?PAGES[u.role]:[]}
function webRO(){const u=webUser();return u&&u.role==='support'}
function webPasskey(){webSignedIn('passkey')}
function webCode(){const w=$('#w-si-code-wrap');if(w.hidden){state.webCode=newCode();w.hidden=false;$('#w-si-code-btn').textContent='Verify code';toast('w',`Email to ${userById($('#w-si-user').value).name.split(' ')[0]}: code ${state.webCode}`);return}if($('#w-si-code').value.trim()!==state.webCode)return showErr('w-si-err',"That code doesn't match. Check your email and try again.");webSignedIn('one-time code')}
function webSignedIn(how){state.webUser=$('#w-si-user').value;const u=webUser();$('#w-si-code').value='';$('#w-si-code-wrap').hidden=true;$('#w-si-code-btn').textContent='Email me a one-time code';showErr('w-si-err');logAudit(actorOf(u),'auth.signin','USER-'+u.id,'Staff website · '+how);wgo(webPages()[0])}
function webSignOut(){const u=webUser();if(u)logAudit(actorOf(u),'auth.signout','USER-'+u.id,'Staff website');state.webUser=null;renderWeb()}
function copyLink(){try{navigator.clipboard.writeText('https://maplegrove.clinicflow.ca/book').catch(()=>{})}catch(e){}toast('w','Booking link copied')}
function setCalView(v){state.calView=v;renderWeb()}
function calShift(n){const d=new Date((n?cur.calDate:CAL_BASE)+'T00:00');if(n){if(state.calView==='week')d.setDate(d.getDate()+7*n);else if(state.calView==='month')d.setMonth(d.getMonth()+n);else d.setDate(d.getDate()+n)}cur.calDate=d.toLocaleDateString('en-CA');syncHash();renderWeb()}
function openDay(iso){cur.calDate=iso;state.calView='day';syncHash();renderWeb()}
function sampleCount(iso,clin){let h=0;for(const ch of iso+clin)h=(h*31+ch.charCodeAt(0))%997;const d=new Date(iso+'T00:00').getDay();if(d===0||d===6)return clin==='lam'&&d===6?6:0;if(clin==='daoud')return d===4?10:0;if(clin==='lam'&&![2,4].includes(d))return 0;return 8+h%6}
function dayCount(iso,clin){return iso===CAL_BASE?bookedCount(clin):sampleCount(iso,clin)}
function dayCap(iso,clin){if(iso===CAL_BASE)return capacity(clin);const d=new Date(iso+'T00:00').getDay();if(clin==='daoud')return d===4?14:0;if(clin==='lam')return [2,4,6].includes(d)?10:0;return d===0||d===6?0:14}
// manual booking from the calendar, with the same lock and write path as online booking
function openManualBooking(clin,time){const u=webUser();if(!u||!['admin','frontdesk'].includes(u.role))return;state.manual={clin:clin||'osei',time:time||null,name:'',phone:'',svc:null};if(time)acquireLock(state.manual.clin,time,'web',120);$('#w-book').hidden=false;renderWeb()}
function manualField(k,v){state.manual[k]=v;if(k==='clin'){state.manual.time=null;releaseLocks('web')}renderWeb()}
function manualPickTime(t){const m=state.manual;if(!acquireLock(m.clin,t,'web',120)){m.err=`${ampm(t)} is being booked online by a patient right now. Pick another time or wait for their hold to run out.`;m.time=null}else{m.err='';m.time=t}renderWeb()}
function manualConfirm(){const m=state.manual,u=webUser();m.name=$('#w-mb-name').value.trim();m.phone=digits($('#w-mb-phone').value);
  if(!m.name||m.phone.length<10||!m.time){m.err='Enter the patient name, a 10-digit phone number and a time.';return renderWeb()}
  const svc=state.services.find(s=>s.clins.includes(m.clin))||state.services[0];const lock=lockAt(m.clin,m.time);const held=lock?Math.round((120000-(lock.until-Date.now()))/1000):0;
  const entry={name:m.name,clin:m.clin,time:m.time,svc:svc.short,svcFull:svc.name,status:'booked',forms:false,phone:m.phone.slice(-4)};
  if(!commitBooking(entry,'web')){m.err='That slot was taken a moment ago. Pick another time.';m.time=null;return renderWeb()}
  logAudit(actorOf(u),'appointment.create','APT-'+(20900+entry.id),`Manual booking · ${clinById(m.clin).short} ${ampm(m.time)} · slot lock held ${held} s`);deliver(m.name,'Booking confirmation','Text → email','Delivered');alertStaff(`${m.name} booked by phone for ${ampm(m.time)} with ${clinById(m.clin).short}.`,'info');
  state.manual=null;$('#w-book').hidden=true;toast('w',`Booked ${entry.name} at ${ampm(entry.time)}`);renderAll()}
function manualClose(){state.manual=null;releaseLocks('web');$('#w-book').hidden=true;renderWeb()}
function runDoubleBookingTest(){
  const clin='osei',t=TIMES.find(t=>tIdx(t)>6&&slotState(clin,t,'test')==='free');if(!t)return toast('w','No free slot left to test with');
  const stamp=clock();const a={name:'Test request A (patient app)',clin,time:t,svc:'Test',status:'booked',forms:true},b={name:'Test request B (front desk)',clin,time:t,svc:'Test',status:'booked',forms:true};
  const ra=commitBooking(a,'test-a'),rb=commitBooking(b,'test-b');
  state.queue=state.queue.filter(q=>q!==a&&q!==b);const doubles=(ra&&rb)?1:0;
  state.dbTests.unshift({t:stamp,slot:`${clinById(clin).short} ${ampm(t)}`,a:ra?'Booked':'Rejected',b:rb?'Booked':'Rejected · slot already taken',doubles});
  logAudit(actorOf(webUser()),'test.concurrent_booking','SLOT '+clin+' '+t,`2 simultaneous requests · ${ra+rb} accepted · ${doubles} double bookings · test bookings removed`);
  toast('w',doubles?'Double booking detected':'One request booked, the other was rejected. 0 double bookings.');renderWeb();
}
function kioskKey(k){const s=state.kiosk;if(s.step!=='enter')return;if(k==='del')s.digits=s.digits.slice(0,-1);else if(k==='clr')s.digits='';else if(s.digits.length<4)s.digits+=k;s.err='';renderWeb()}
function kioskFind(){const s=state.kiosk;if(s.digits.length<4){s.err='Enter the last 4 digits of your phone number.';return renderWeb()}const m=state.queue.filter(q=>q.phone===s.digits&&['booked','confirmed','late'].includes(q.status));if(!m.length){s.err="We couldn't find a visit today for that number. Please see the front desk.";return renderWeb()}s.matches=m.map(q=>q.id);s.step='confirm';renderWeb()}
function kioskCheckIn(id){const q=state.queue.find(x=>x.id===id);checkInEntry(q,'front-desk tablet',`${q.name} (patient, tablet)`);if(q.mine)notifyPatient(`You're checked in. Ticket ${q.ticket}.`,'push','good');state.kiosk={step:'done',digits:'',ticket:q.ticket,id};renderAll();clearTimeout(state.kioskT);state.kioskT=setTimeout(()=>{state.kiosk={step:'enter',digits:''};renderWeb()},8000)}
function kioskReset(){state.kiosk={step:'enter',digits:''};renderWeb()}
function setRule(k,v){const u=webUser();const prev=state.rules[k];state.rules[k]=v;logAudit(actorOf(u),'settings.update','CLINIC',`${k}: ${prev} → ${v}`);toast('w','Saved');renderAll()}
function runReminderJob(){
  const u=webUser();let push=0,sms=0;
  state.upcoming.forEach((p,i)=>{const fallback=i%2===1;push++;if(fallback)sms++;deliver(p.name,`Reminder, ${p.h} h`,fallback?'Push → text':'Push',fallback?'Push not opened in 30 min; text delivered':'Delivered')});
  state.queue.filter(q=>q.status==='booked'&&ACTIVE(q)).forEach(q=>{deliver(q.name,'Same-day nudge, one-tap confirm','Push → text','Delivered');if(q.mine)notifyPatient(`Reminder: ${q.svc} today ${ampm(q.time)} with ${clinById(q.clin).short}. Tap to confirm.`,'push','info','confirm')});
  logAudit(SYSTEM,'notification.job',`${state.upcoming.length} reminders`,`Run by ${u?u.name:'scheduler'} · 24 h and 48 h reminders · ${push} push, ${sms} text fallback`);
  toast('w',`Sent ${state.upcoming.length} reminders (${push} push, ${sms} fell back to text)`);touch();renderAll();
}
function sendAnnouncement(){const t=$('#w-announce').value.trim();if(!t)return toast('w','Write the announcement first');state.notice=t;notifyPatient('Clinic notice: '+t,'push','mute');deliver('All patients with visits this week','Clinic announcement','Push → email','Delivered to 41');logAudit(actorOf(webUser()),'notification.sent','CLINIC','Clinic announcement to 41 patients');toast('w','Announcement sent to 41 patients');renderAll()}
function addService(prefix='w'){const name=$(`#${prefix}-svc-name`).value.trim();if(!name)return toast('w','Name the service first');const dur=+$(`#${prefix}-svc-dur`).value,online=$(`#${prefix}-svc-online`).value==='1';state.services.splice(state.services.length-1,0,{name,short:name.split('·')[0].trim(),dur,buf:0,online,who:online?'New and returning':'Front desk only',form:'Contact, consent',clins:['osei','lam']});logAudit(actorOf(webUser()),'service.create','SERVICE',`${name} · ${dur} min · ${online?'bookable online':'front desk only'}`);$(`#${prefix}-svc-name`).value='';toast('w',`${name} added. Patients can book it now.`);renderAll()}
function toggleOnline(i){const s=state.services[i];s.online=!s.online;s.who=s.online?'New and returning':'Front desk only';logAudit(actorOf(webUser()),'service.update','SERVICE',`${s.name}: ${s.online?'bookable online':'front desk only'}`);renderAll()}
function addClinician(prefix='w'){const name=$(`#${prefix}-clin-name`).value.trim(),role=$(`#${prefix}-clin-role`).value.trim()||'Clinician';if(!name)return toast('w','Enter the clinician name');const id='c'+(state.nextId++);state.clins.splice(state.clins.length-1,0,{id,name,short:name.split(',')[0],role,hours:'Mon–Fri 9–5'});state.services.forEach(s=>{if(/physio/i.test(role)&&s.name.startsWith('Physio'))s.clins.push(id)});logAudit(actorOf(webUser()),'clinician.create','CLIN-'+id,`${name} · ${role}`);$(`#${prefix}-clin-name`).value='';$(`#${prefix}-clin-role`).value='';toast('w',`${name} added to the calendar`);renderAll()}
function addTimeOff(){const clin=$('#w-to-clin').value,type=$('#w-to-type').value,when=$('#w-to-when').value.trim();if(!when)return toast('w','Say when, for example "Tue 2:30" or "Oct 12–16"');state.timeoff.push({clin,type,when});const m=when.match(/^Tue (\d{1,2}:\d{2})$/i);let note='';if(m&&TIMES.includes(m[1])){if(apptAt(clin,m[1]))note=' (there is already a booking then; move it first)';else state.blocks.push({clin,time:m[1],type})}logAudit(actorOf(webUser()),'schedule.timeoff','CLIN-'+clin,`${type} · ${when}`);$('#w-to-when').value='';toast('w',`${type} added for ${clinById(clin).short}${note}`);renderAll()}
function addBlockType(){const el=$('#w-block-name'),name=el.value.trim();if(!name){toast('w','Name the type first');el.focus();return}state.blockTypes.push({name,scope:$('#w-block-who').value});el.value='';logAudit(actorOf(webUser()),'settings.update','CLINIC',`Unavailable time type added: ${name}`);toast('w',`${name} added`);renderWeb()}
function inviteUser(prefix='w'){const name=$(`#${prefix}-inv-name`).value.trim(),email=$(`#${prefix}-inv-email`).value.trim(),role=$(`#${prefix}-inv-role`).value;if(!name||!email.includes('@'))return toast('w','Enter a name and an email address');const id='u'+(state.nextId++);state.users.push({id,name,role,signin:'Invite sent · passkey on first sign-in',last:'Invited'});logAudit(actorOf(webUser()),'user.invite','USER-'+id,`${name} · ${ROLES[role]}`);$(`#${prefix}-inv-name`).value='';$(`#${prefix}-inv-email`).value='';toast('w',`Invite sent to ${email}`);renderAll()}
function setUserRole(id,role){const x=userById(id),prev=x.role;if(id===state.webUser&&role!=='admin')return toast('w',"You can't remove your own admin access");x.role=role;if(role==='clinician'&&!x.clin)x.clin='osei';logAudit(actorOf(webUser()),'role.update','USER-'+id,`${ROLES[prev]} → ${ROLES[role]}`);toast('w',`${x.name} is now ${ROLES[role]}`);renderAll()}
function missedAct(id,st){const m=state.missed.find(x=>x.id===id);m.status=st;logAudit(actorOf(webUser()),'missed.'+st,m.name,`${m.date} ${m.time}`);if(st==='contacted')deliver(m.name,'Missed visit follow-up','Text → email','Delivered');toast('w',{contacted:`Rebooking link sent to ${m.name.split(' ')[0]} by text`,excused:'Excused. Not counted in the no-show rate',rebooked:'Marked rebooked'}[st]);renderWeb()}
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
  $$('.page').forEach(p=>p.classList.toggle('active',p.dataset.p===cur.web));$$('.side button').forEach(b=>b.setAttribute('aria-selected',b.dataset.p===cur.web));
  $('#w-ro').hidden=!webRO();
  $('#w-clinic-name').textContent=state.setup.profile.name;
  const canBook=['admin','frontdesk'].includes(u.role);
  const act=state.queue.filter(ACTIVE),clinsShown=state.clins.filter(c=>u.role!=='clinician'||c.id===u.clin);
  // dashboard
  const bookable=state.clins.filter(c=>!c.room),cap=bookable.reduce((t,c)=>t+capacity(c.id),0),bk=bookable.reduce((t,c)=>t+bookedCount(c.id),0);
  const waiting=state.queue.filter(q=>q.status==='waiting'),avgW=waiting.length?Math.round(waiting.reduce((t,q)=>t+waitMins(q),0)/waiting.length):0;
  const formsDone=act.filter(q=>q.forms).length;
  $('#w-kpis').innerHTML=`<div class="kpi"><p class="eyebrow">Booked today</p><b class="num">${bk}</b><span class="delta muted">of ${cap} slots · ${Math.round(bk/cap*100)}%</span></div><div class="kpi"><p class="eyebrow">In waiting room</p><b class="num">${waiting.length}</b><span class="delta muted">average wait ${avgW} min</span></div><div class="kpi"><p class="eyebrow">No-show rate, 30 days</p><b class="num">6.1%</b><span class="delta" style="color:var(--good)">${ic('down','ic ic-inline')} 2.3 pts vs prior 30 days</span></div><div class="kpi"><p class="eyebrow">Freed slots refilled</p><b class="num">${Math.round(state.recovery.refilled/state.recovery.total*100)}%</b><span class="delta muted">${state.recovery.refilled} of ${state.recovery.total} this month</span></div><div class="kpi"><p class="eyebrow">Intake complete</p><b class="num">${formsDone} / ${act.length}</b><span class="delta" style="color:var(--warn)">${act.length-formsDone} forms open</span></div>`;
  const attn=[];
  state.queue.filter(q=>q.status==='late').forEach(q=>attn.push(`<tr><td>${pill('late')}</td><td>${esc(q.name)} · ${ampm(q.time)} with ${clinById(q.clin).short}</td><td class="muted">not checked in</td><td>${canBook?`<button class="btn sm" onclick="remindPatient(${q.id})">Text</button> <button class="btn sm" onclick="webNoShow(${q.id})">Mark no-show</button>`:''}</td></tr>`));
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
        if(q)cell=`<div class="appt ${['late','noshow'].includes(q.status)?'crit':q.status==='confirmed'||q.status==='done'?'conf':q.status==='booked'?'':'good'}" title="${esc(q.name)} · ${STATUS[q.status][1]}">${esc(q.name)}<br>${STATUS[q.status][1]}</div>`;
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
  if(m){const free=TIMES.filter(t=>{const s=slotState(m.clin,t,'web');return s==='free'||s==='freed'||t===m.time});const lk=m.time&&lockAt(m.clin,m.time);
    $('#w-book').innerHTML=`<div class="row between"><h3>New booking (front desk)</h3><button class="btn sm ghost" onclick="manualClose()">Close</button></div><div class="form-row"><input class="btn sm" id="w-mb-name" placeholder="Patient name" value="${esc(m.name)}" oninput="state.manual.name=this.value"><input class="btn sm" id="w-mb-phone" placeholder="Mobile number" value="${esc(m.phone)}" oninput="state.manual.phone=this.value"><select class="btn sm" onchange="manualField('clin',this.value)">${state.clins.map(c=>`<option value="${c.id}" ${c.id===m.clin?'selected':''}>${esc(c.short)}</option>`).join('')}</select><select class="btn sm" onchange="manualPickTime(this.value)"><option value="">Time…</option>${TIMES.map(t=>{const s=slotState(m.clin,t,'web');const ok=s==='free'||s==='freed'||t===m.time;return `<option value="${t}" ${t===m.time?'selected':''} ${ok?'':'disabled'}>${ampm(t)}${ok?'':' · '+({taken:'taken',blocked:'unavailable',held:'held online',offered:'offered to waitlist'}[s]||'')}</option>`}).join('')}</select><button class="btn sm primary" onclick="manualConfirm()">Book</button></div>${lk?`<p class="small" style="color:var(--warn)">${ic('lock','ic ic-inline')} ${ampm(m.time)} is locked for you for ${Math.max(0,Math.round((lk.until-Date.now())/1000))} s. Nobody else can book it meanwhile.</p>`:''}${m.err?`<p class="err">${esc(m.err)}</p>`:''}<p class="small muted">${free.length} open times with ${clinById(m.clin).short} today.</p>`}
  $('#w-db-count').textContent=`${state.dbTests.length} tests · ${state.dbTests.reduce((t,x)=>t+x.doubles,0)} double bookings`;
  $('#w-db-log').innerHTML=state.dbTests.length?'<tr><th>Time</th><th>Slot</th><th>Request A</th><th>Request B</th><th>Double bookings</th></tr>'+state.dbTests.map(x=>`<tr><td class="num">${x.t}</td><td>${x.slot}</td><td>${x.a}</td><td>${x.b}</td><td class="num">${x.doubles}</td></tr>`).join(''):'';
  // live queue and TV board
  const arrived=state.queue.filter(q=>['checked','waiting','invisit','done','late'].includes(q.status)&&(u.role!=='clinician'||q.clin===u.clin));
  $('#w-queue').innerHTML='<tr><th>Ticket</th><th>Patient</th><th>Clinician</th><th>Appt</th><th>Status</th><th>Waited</th><th>Forms</th></tr>'+arrived.map(q=>`<tr><td class="num">${q.ticket||'—'}</td><td>${esc(q.name)}</td><td class="muted">${clinById(q.clin).short}</td><td class="num">${ampm(q.time)}</td><td>${pill(q.status)}</td><td class="num">${q.status==='waiting'?waitMins(q)+' min':''}</td><td>${q.forms?'<span class="pill good">Done</span>':'<span class="pill warn">Open</span>'}</td></tr>`).join('');
  const nextT=state.queue.filter(q=>q.status==='waiting').map(q=>q.ticket).sort().slice(0,3);
  $('#w-tv').innerHTML=`<p class="eyebrow" style="color:inherit;opacity:.7">Now serving</p><div class="now">${nowServing()||'—'}</div><div class="up">${nextT.length?nextT.map((t,i)=>`<span>${i?'':'Next: '}${t}</span>`).join(''):'<span>No one waiting</span>'}</div><p class="small" style="opacity:.7;margin-top:12px">Ticket numbers only. No names on the board.</p>`;
  // kiosk
  const k=state.kiosk;
  $('#w-kiosk').innerHTML=k.step==='enter'?`<div class="kiosk-screen"><h3>Welcome to ${esc(state.setup.profile.name)}</h3><p class="muted">Check in for today's visit. Enter the last 4 digits of your phone number.</p><div class="kiosk-digits" aria-live="polite">${[0,1,2,3].map(i=>`<span>${k.digits[i]||''}</span>`).join('')}</div><div class="keypad">${['1','2','3','4','5','6','7','8','9','clr','0','del'].map(x=>`<button onclick="kioskKey('${x}')" aria-label="${x==='del'?'Delete':x==='clr'?'Clear':x}">${x==='del'?ic('left'):x==='clr'?'Clear':x}</button>`).join('')}</div>${k.err?`<p class="err">${esc(k.err)}</p>`:''}<button class="btn primary block" onclick="kioskFind()">Continue</button><p class="small muted">Try 0142 (Priya Raman), 7788 or 4410.</p></div>`
    :k.step==='confirm'?`<div class="kiosk-screen"><h3>Is this you?</h3><div class="stack">${k.matches.map(id=>{const q=state.queue.find(x=>x.id===id);return `<button class="choice" onclick="kioskCheckIn(${id})"><div class="avatar">${initials(q.name)}</div><div class="grow"><div class="t">${initials(q.name).split('').join('. ')}.</div><div class="small muted">${ampm(q.time)} with ${clinById(q.clin).short}</div></div></button>`}).join('')}</div><button class="btn block" onclick="kioskReset()">That's not me</button><p class="small muted">Only initials are shown here, for privacy.</p></div>`
    :`<div class="kiosk-screen"><div class="avatar big-check">${ic('check')}</div><h3>You're checked in</h3><p>Your ticket is <b class="num">${k.ticket}</b>. Please take a seat; the board will show your number.</p><button class="btn block" onclick="kioskReset()">Done</button></div>`;
  // waitlist and recovery
  $('#w-wait-kpis').innerHTML=`<div class="kpi"><p class="eyebrow">Freed slots refilled</p><b class="num">${state.recovery.refilled} / ${state.recovery.total}</b><span class="delta muted">${Math.round(state.recovery.refilled/state.recovery.total*100)}% recovery</span></div><div class="kpi"><p class="eyebrow">Fastest offer today</p><b class="num">${fmtSecs(Math.min(...state.freed.flatMap(f=>f.offers.map(o=>o.after)),9999)||0)}</b><span class="delta" style="color:var(--good)">target under 5 min</span></div><div class="kpi"><p class="eyebrow">On the waitlist</p><b class="num">${state.waitlist.filter(w=>['waiting','offered'].includes(w.status)).length}</b><span class="delta muted">${state.waitlist.filter(w=>w.priority).length} flagged priority</span></div>`;
  $('#w-offers').innerHTML='<tr><th>Slot</th><th>Freed</th><th>Offered to</th><th>Sent after</th><th>Status</th></tr>'+state.freed.map(f=>{const o=f.offers.at(-1);return `<tr><td>${clinById(f.clin).short} ${ampm(f.time)}</td><td class="num">${f.freedClock} · ${esc(f.reason)}</td><td>${o?esc(o.name):'—'}${f.offers.length>1?` <span class="small muted">(${f.offers.length} tries)</span>`:''}</td><td class="num">${o?fmtSecs(o.after)+(o.after<300?' ✓':''):'—'}</td><td>${f.status==='filled'?`<span class="pill good">Refilled · ${esc(f.filledBy)}</span>`:f.status==='offered'?`<span class="pill warn">Holding · ${state.rules.hold} min</span>`:f.status==='held'?'<span class="pill mute">Held for phone</span>':'<span class="pill mute">Open online</span>'}</td></tr>`}).join('');
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
  $('#w-blocks').innerHTML='<tr><th>Type</th><th>Applies to</th><th>On the calendar</th><th></th></tr>'+state.blockTypes.map((b,i)=>`<tr><td>${esc(b.name)}</td><td class="muted">${b.scope}</td><td style="width:140px"><div class="appt off" style="height:22px">${esc(b.name)}</div></td><td style="text-align:right"><button class="btn sm" onclick="state.blockTypes.splice(${i},1);renderWeb();toast('w','Type removed')">Remove</button></td></tr>`).join('');
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
  const P=s.profile,url=`https://${P.name.toLowerCase().replace(/[^a-z]+/g,'')}.clinicflow.ca/book`;
  const bodies={
    1:`<h3>Clinic profile and branding</h3><div class="form-grid"><div class="field"><label for="sw-name">Clinic name</label><input id="sw-name" value="${esc(P.name)}"></div><div class="field"><label for="sw-phone">Phone</label><input id="sw-phone" value="${esc(P.phone)}"></div><div class="field"><label for="sw-addr">Address</label><input id="sw-addr" value="${esc(P.address)}"></div><div class="field"><label>Brand colour</label><div class="swatches">${Object.keys(BRANDS).map(b=>`<button class="swatch ${P.brand===b?'on':''}" style="background:${BRANDS[b][0]}" onclick="setBrand('${b}')" aria-label="${b}" aria-pressed="${P.brand===b}"></button>`).join('')}</div></div></div><p class="small muted">One location for now. Patients see this name, address and colour on the booking page and in messages.</p>`,
    2:`<h3>Services and how long they take</h3><div class="list">${state.services.map(x=>`<div class="item"><div class="grow"><div class="t">${esc(x.name)}</div><div class="s">${x.dur} min · ${x.online?'bookable online':'front desk only'}</div></div></div>`).join('')}</div><div class="form-row"><input class="btn sm" id="sw-svc-name" placeholder="Add a service"><select class="btn sm" id="sw-svc-dur"><option>15</option><option selected>30</option><option>45</option><option>60</option></select><select class="btn sm" id="sw-svc-online"><option value="1">Bookable online</option><option value="0">Front desk only</option></select><button class="btn sm" onclick="addService('sw')">Add</button></div>`,
    3:`<h3>Clinicians and their hours</h3><div class="list">${state.clins.map(c=>`<div class="item"><div class="avatar">${initials(c.name)}</div><div class="grow"><div class="t">${esc(c.name)}</div><div class="s">${esc(c.role)} · ${c.hours}</div></div></div>`).join('')}</div><div class="form-row"><input class="btn sm" id="sw-clin-name" placeholder="Name"><input class="btn sm" id="sw-clin-role" placeholder="Role"><button class="btn sm" onclick="addClinician('sw')">Add</button></div><p class="small muted">Breaks and time off can be added later under Services &amp; clinicians.</p>`,
    4:`<h3>Existing appointments (optional)</h3><p class="small muted">No spreadsheet is needed to finish setup.</p><div class="stack">${[['fresh','Start fresh: patients book through your link from now on (recommended)'],['hand','Add upcoming appointments by hand in the Calendar'],['file','Upload a calendar export (.ics) later']].map(([k,l])=>`<label class="chk"><input type="radio" name="sw-ex" ${s.existing===k?'checked':''} onchange="state.setup.existing='${k}'"><span class="small">${l}</span></label>`).join('')}</div>`,
    5:`<h3>Your public booking link</h3><div class="row" style="flex-wrap:wrap"><code class="tpl" style="flex:1;min-width:200px">${url.replace('https://','')}</code><button class="btn sm" onclick="copyLink()">Copy</button></div><div class="row" style="gap:16px;align-items:flex-start;flex-wrap:wrap"><div class="qr">${qrSvg(url)}</div><div class="small stack" style="flex:1;min-width:200px"><p>Print this for the front desk, the door and appointment cards. Patients scan it, pick a time and confirm with a text code. No app or account needed.</p><div class="row"><button class="btn sm" onclick="surface('patient',$$('.switch button')[0]);startBooking()">Open it as a patient</button></div></div></div>`,
    6:`<h3>Reminder and waitlist rules</h3><label class="chk"><input type="checkbox" ${state.rules.remind48?'checked':''} onchange="setRule('remind48',this.checked)"><span class="small">Reminder 48 hours before, with one-tap confirm (push, then email)</span></label><label class="chk"><input type="checkbox" ${state.rules.remind24?'checked':''} onchange="setRule('remind24',this.checked)"><span class="small">Reminder 24 hours before (push, then text)</span></label><div class="form-grid"><div class="field"><label for="sw-cw">Cancellation window</label><select id="sw-cw" onchange="setRule('cancelWindow',+this.value)">${[12,24,48].map(x=>`<option value="${x}" ${state.rules.cancelWindow===x?'selected':''}>${x} hours</option>`).join('')}</select></div><div class="field"><label for="sw-ho">Waitlist offer holds for</label><select id="sw-ho" onchange="setRule('hold',+this.value)">${[15,30,60].map(x=>`<option value="${x}" ${state.rules.hold===x?'selected':''}>${x} minutes</option>`).join('')}</select></div></div>`,
    7:`<h3>Invite your staff</h3><div class="list">${state.users.map(x=>`<div class="item"><div class="avatar">${initials(x.name)}</div><div class="grow"><div class="t">${esc(x.name)}</div><div class="s">${ROLES[x.role]} · ${x.last}</div></div></div>`).join('')}</div><div class="form-row"><input class="btn sm" id="sw-inv-name" placeholder="Name"><input class="btn sm" id="sw-inv-email" placeholder="Email"><select class="btn sm" id="sw-inv-role"><option value="frontdesk">Front desk</option><option value="clinician">Clinician</option><option value="support">Support</option><option value="admin">Admin</option></select><button class="btn sm" onclick="inviteUser('sw')">Invite</button></div>`,
    8:`<h3>ClinicFlow directory (optional)</h3><label class="chk"><input type="checkbox" ${s.listed?'checked':''} onchange="state.setup.listed=this.checked;renderWeb()"><span class="small">List ${esc(P.name)} so nearby patients can find openings</span></label>${s.listed?`<div class="item card"><div class="avatar">${initials(P.name)}</div><div class="grow"><div class="t">${esc(P.name)}</div><div class="s">${esc(P.address)} · ${state.services.filter(x=>x.online).length} services online · next opening today 2:30 pm</div></div></div>`:''}<p class="small muted">Only availability is shared. Never patient names or reasons for visits.</p>`,
  };
  $('#w-step-body').innerHTML=bodies[s.step]+(s.finished&&s.step===8?`<div class="banner good-banner">Setup complete in ${elapsed()}. The target is under 60 minutes.</div>`:'')+`<div class="row between" style="margin-top:6px"><button class="btn ghost" onclick="setupGo(${Math.max(1,s.step-1)})" ${s.step===1?'disabled':''}>Back</button><button class="btn sm" onclick="setupRestart()">Restart timed test</button><button class="btn primary" onclick="setupNext()">${s.step===8?'Finish setup':'Save and continue'}</button></div>`;
}
function webNoShow(id){const q=state.queue.find(x=>x.id===id),u=webUser();q.status='noshow';logAudit(actorOf(u),'appointment.status','APT-'+(20900+q.id),'Late → No-show');state.missed.unshift({id:Date.now(),date:'Today',time:ampm(q.time),name:q.name,clin:clinById(q.clin).short,svc:q.svc,reminder:'Delivered, no reply',prior:0,status:'open'});alertStaff(`${q.name} marked no-show for ${ampm(q.time)}.`,'crit');toast('w','Marked no-show');touch();renderAll()}
function unconfirmedRemind(){state.queue.filter(q=>q.status==='booked').forEach(q=>remindPatient(q.id));toast('w','Reminders sent')}
function formsAll(){state.queue.filter(q=>ACTIVE(q)&&!q.forms&&!['done','invisit'].includes(q.status)).forEach(q=>sendForm(q.id));toast('w','Form links sent')}

// ---------- theme ----------
function syncThemeButton(){const dark=document.documentElement.dataset.theme==='dark';$('#theme-toggle').setAttribute('aria-pressed',dark);$('#theme-label').textContent=dark?'Light mode':'Dark mode'}
function toggleTheme(){const dark=document.documentElement.dataset.theme!=='dark';if(dark)document.documentElement.dataset.theme='dark';else delete document.documentElement.dataset.theme;try{localStorage.setItem('cf-theme',dark?'dark':'light')}catch(e){}syncThemeButton()}

// ---------- live ticker: queue freshness, lock countdowns, setup timer ----------
state.kiosk={step:'enter',digits:''};
setInterval(()=>{
  const ago=Math.round((Date.now()-state.lastChange)/1000),txt=`Live · last change ${ago<2?'just now':ago+' s ago'} · every device updates within 1 s`;
  const sl=$('#s-live'),wl=$('#w-live');if(sl)sl.textContent=txt;if(wl)wl.textContent=txt;
  let expired=false;for(const k in state.locks)if(state.locks[k].until<=Date.now()){delete state.locks[k];expired=true}
  if(expired&&state.booking.time&&!lockAt(state.booking.lockedClin,state.booking.time)&&['book2','book3','otp'].includes(cur.patient)){showErr('p-slot-err','Your hold on that time ran out. Pick a time again.');state.booking.time=null}
  if(cur.surface==='patient'&&cur.patient==='book2'||expired)renderPatient();
  if(cur.surface==='web'&&(cur.web==='cal'||cur.web==='setup'||expired))renderWeb();
},1000);
// OTP boxes: move to the next box as you type, back on delete
$$('#p-otp input').forEach((inp,i,all)=>{inp.addEventListener('input',()=>{inp.value=digits(inp.value).slice(-1);if(inp.value&&all[i+1])all[i+1].focus()});inp.addEventListener('keydown',e=>{if(e.key==='Backspace'&&!inp.value&&all[i-1])all[i-1].focus()});inp.addEventListener('paste',e=>{const t=digits(e.clipboardData.getData('text'));if(t.length===6){e.preventDefault();[...t].forEach((d,j)=>all[j].value=d)}})});

function renderAll(){renderPatient();renderStaff();renderWeb()}
$('#hint').textContent=hints.patient;
renderAll();
syncThemeButton();
openFromHash();
