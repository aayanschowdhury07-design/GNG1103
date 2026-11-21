// French for the staff website, group b (see l10n.dart). Keys are the English text exactly as in the code.
const frB = <String, String>{
  // ---- setup steps (setupSteps in clinicflow_firebase)
  'Clinic profile & branding': 'Profil et image de la clinique',
  'Services & durations': 'Services et durées',
  'Clinicians & hours': 'Cliniciens et horaires',
  'Existing appointments': 'Rendez-vous existants',
  'Booking link & QR code': 'Lien de réservation et code QR',
  'Reminder & waitlist rules': 'Règles de rappel et de liste d’attente',
  'Invite staff, set roles': 'Inviter le personnel, attribuer les rôles',
  'Directory listing': 'Inscription au répertoire',

  // ---- weekdays (display only; stored values stay English)
  'Mon': 'lun.',
  'Tue': 'mar.',
  'Wed': 'mer.',
  'Thu': 'jeu.',
  'Fri': 'ven.',
  'Sat': 'sam.',
  'Sun': 'dim.',

  // ---- staff roles (staffRoles)
  'Admin': 'Administrateur',
  'Front desk': 'Réception',
  'Clinician': 'Clinicien',
  'Support': 'Soutien',

  // ---- step frame
  'Couldn’t save: {e}': 'Enregistrement impossible : {e}',
  'Step {n} of {total}': 'Étape {n} sur {total}',
  'Back': 'Retour',
  'Finish setup': 'Terminer la configuration',
  'Save and continue': 'Enregistrer et continuer',

  // ---- 1. profile
  'Physiotherapy': 'Physiothérapie',
  'Chiropractic': 'Chiropratique',
  'Massage therapy': 'Massothérapie',
  'Family practice': 'Médecine familiale',
  'Walk-in': 'Sans rendez-vous',
  'Mental health': 'Santé mentale',
  'Rehab': 'Réadaptation',
  'Dental': 'Dentaire',
  'Enter the clinic’s name.': 'Entrez le nom de la clinique.',
  'Enter the street address patients come to.': 'Entrez l’adresse civique où se rendent les patients.',
  'Enter the clinic’s phone number with area code.': 'Entrez le numéro de téléphone de la clinique avec l’indicatif régional.',
  'Choose at least one kind of care, so patients can find you.': 'Choisissez au moins un type de soins pour que les patients vous trouvent.',
  'Click the map where the clinic is, so it shows in the right place.': 'Cliquez sur la carte à l’emplacement de la clinique pour qu’elle s’affiche au bon endroit.',
  'Patients see this name, address and colour on the booking page, in messages and in the clinic directory.':
      'Les patients voient ce nom, cette adresse et cette couleur sur la page de réservation, dans les messages et dans le répertoire des cliniques.',
  'Clinic': 'Clinique',
  'Clinic name': 'Nom de la clinique',
  'Phone': 'Téléphone',
  'Street address': 'Adresse civique',
  'City and province': 'Ville et province',
  'e.g. Toronto, ON': 'p. ex. Montréal (QC)',
  'Kind of care': 'Type de soins',
  'Patients search the directory by these.': 'Les patients font leurs recherches dans le répertoire selon ces critères.',
  'Where patients find you': 'Où les patients vous trouvent',
  'Pinned. Drag the map or click again to adjust.': 'Épinglé. Faites glisser la carte ou cliquez de nouveau pour ajuster.',
  'Click the map where the clinic’s entrance is.': 'Cliquez sur la carte à l’emplacement de l’entrée de la clinique.',
  'OpenStreetMap contributors': 'Contributeurs d’OpenStreetMap',
  'Brand colour': 'Couleur de la marque',
  '{colour} brand colour': 'Couleur de marque {colour}',
  'blue': 'bleu',
  'teal': 'sarcelle',
  'green': 'vert',
  'plum': 'prune',
  'Languages': 'Langues',
  'Patient messages and the booking page are offered in these.': 'Les messages aux patients et la page de réservation sont offerts dans ces langues.',
  'One location for now. Clinics with several locations come later.': 'Un seul emplacement pour l’instant. Les cliniques à plusieurs emplacements viendront plus tard.',

  // ---- 2. services
  'What patients can book, and how long each visit takes. You choose who offers each one in the next step.':
      'Ce que les patients peuvent réserver et la durée de chaque rendez-vous. Vous choisirez qui offre chaque service à l’étape suivante.',
  'Add at least one service.': 'Ajoutez au moins un service.',
  'Name the service first.': 'Nommez d’abord le service.',
  'Services': 'Services',
  'None yet. Add your first one below.': 'Aucun pour l’instant. Ajoutez le premier ci-dessous.',
  '{n} min': '{n} min',
  'Bookable online': 'Réservable en ligne',
  'Front desk only': 'Réception seulement',
  'Remove {name}': 'Retirer {name}',
  'Add a service': 'Ajouter un service',
  'Name': 'Nom',
  'e.g. Physiotherapy · follow-up': 'p. ex. Physiotherapy · follow-up',
  'French name (optional)': 'Nom en français (facultatif)',
  'e.g. Physiothérapie · suivi': 'p. ex. Physiothérapie · suivi',
  'Length': 'Durée',
  'Who it’s for (optional)': 'Pour qui (facultatif)',
  'e.g. Returning patients': 'p. ex. Patients existants',
  'Add service': 'Ajouter le service',

  // ---- 3. clinicians
  'Who sees patients, the days and hours they work, and which services they offer. Breaks and time off can be added later.':
      'Qui voit les patients, leurs jours et heures de travail, et les services qu’ils offrent. Les pauses et les congés pourront être ajoutés plus tard.',
  'Add at least one clinician.': 'Ajoutez au moins un clinicien.',
  'Enter the clinician’s name.': 'Entrez le nom du clinicien.',
  'Enter their role, e.g. Physiotherapist.': 'Entrez son rôle, p. ex. Physiothérapeute.',
  'Pick the days they work.': 'Choisissez ses jours de travail.',
  'The end of their day must be after the start.': 'La fin de sa journée doit être après le début.',
  'Clinicians': 'Cliniciens',
  '{from} to {to}': '{from} à {to}',
  'Offers: {services}': 'Offre : {services}',
  'no services yet': 'aucun service pour l’instant',
  'Edit hours for {name}': 'Modifier les heures de {name}',
  'Nobody offers {services} yet, so patients can’t book it.': 'Personne n’offre encore {services} : les patients ne peuvent donc pas le réserver.',
  'Add a clinician': 'Ajouter un clinicien',
  'e.g. Dr. Kwame Osei': 'p. ex. Dr Kwame Osei',
  'Role': 'Rôle',
  'e.g. Physiotherapist': 'p. ex. Physiothérapeute',
  'Days': 'Jours',
  'Starts': 'Début',
  'Ends': 'Fin',
  'Offers': 'Offre',
  'Add services in step 2 first.': 'Ajoutez d’abord des services à l’étape 2.',
  'Add clinician': 'Ajouter le clinicien',
  'Hours for {name}': 'Heures de {name}',
  'Cancel': 'Annuler',
  'Save': 'Enregistrer',

  // ---- 4. existing appointments
  'Optional. No spreadsheet is needed to finish setup.': 'Facultatif. Aucun tableur n’est nécessaire pour terminer la configuration.',
  'Start fresh': 'Repartir à zéro',
  'Patients book through your link from now on. Recommended.': 'Les patients réservent désormais au moyen de votre lien. Recommandé.',
  'Add upcoming appointments by hand': 'Ajouter les rendez-vous à venir manuellement',
  'From the calendar once setup is done.': 'À partir du calendrier, une fois la configuration terminée.',
  'Import a calendar file later': 'Importer un fichier de calendrier plus tard',
  'An .ics export from your current system.': 'Une exportation .ics de votre système actuel.',

  // ---- 5. booking link
  'Patients scan this or tap the link, pick a time and confirm with a text code. No app or account needed.':
      'Les patients balayent ce code ou touchent le lien, choisissent une heure et confirment avec un code reçu par texto. Aucune application ni aucun compte requis.',
  'QR code for {url}': 'Code QR pour {url}',
  'Your booking link': 'Votre lien de réservation',
  'Print the QR code for the front desk, the door and appointment cards.': 'Imprimez le code QR pour la réception, la porte et les cartes de rendez-vous.',
  'The link starts working when the patient web app is published (Firebase Hosting).':
      'Le lien fonctionnera dès que l’application Web des patients sera publiée (Firebase Hosting).',

  // ---- 6. rules
  'How cancellations, waitlist offers and reminders work at your clinic. Every change is recorded in the audit log.':
      'Le fonctionnement des annulations, des offres et des rappels à votre clinique. Chaque modification est consignée dans le journal d’audit.',
  'Cancellations and booking': 'Annulations et réservation',
  'Free cancellation until': 'Annulation gratuite jusqu’à',
  '12 hours before': '12 heures avant',
  '24 hours before': '24 heures avant',
  '48 hours before': '48 heures avant',
  'Same-day online booking': 'Réservation en ligne le jour même',
  'Up to 1 hour before': 'Jusqu’à 1 heure avant',
  'Up to 2 hours before': 'Jusqu’à 2 heures avant',
  'Not allowed': 'Non permise',
  'Waitlist': 'Liste d’attente',
  'When a time frees up, it is offered to the first matching person on the waitlist.':
      'Quand une plage se libère, elle est offerte à la première personne admissible de la liste d’attente.',
  'An offer is held for': 'Une offre est réservée pendant',
  '15 minutes': '15 minutes',
  '30 minutes': '30 minutes',
  '1 hour': '1 heure',
  'Reminders': 'Rappels',
  'Each reminder has a one-tap confirm.': 'Chaque rappel se confirme d’un seul toucher.',
  '48 hours before (push, then email)': '48 heures avant (notification push, puis courriel)',
  '24 hours before (push, then text)': '24 heures avant (notification push, puis texto)',

  // ---- 7. staff
  'Enter their name.': 'Entrez son nom.',
  'Enter their work email.': 'Entrez son courriel professionnel.',
  'Optional. Each person signs in with their own account, and their role decides what they can see and change.':
      'Facultatif. Chaque personne se connecte avec son propre compte, et son rôle détermine ce qu’elle peut voir et modifier.',
  'Your team': 'Votre équipe',
  '{name} (you)': '{name} (vous)',
  '{email} · invited, hasn’t signed in yet': '{email} · invitation envoyée, pas encore connecté',
  'Cancel invitation for {name}': 'Annuler l’invitation de {name}',
  'Invite someone': 'Inviter une personne',
  'Admins can change everything; front desk runs the day; clinicians see their own patients; support has read-only access.':
      'Les administrateurs peuvent tout modifier; la réception gère la journée; les cliniciens voient leurs propres patients; le soutien a un accès en lecture seule.',
  'Work email': 'Courriel professionnel',
  'Add invitation': 'Ajouter l’invitation',
  'Invitation emails aren’t sent yet: ask each person to create an account on this site with the email you entered.':
      'Les courriels d’invitation ne sont pas encore envoyés : demandez à chaque personne de créer un compte sur ce site avec le courriel que vous avez saisi.',

  // ---- 8. directory
  'Optional. Listed clinics appear in the ClinicFlow app’s clinic map and search, so nearby patients can find your openings.':
      'Facultatif. Les cliniques inscrites apparaissent sur la carte et dans la recherche de l’application ClinicFlow, pour que les patients à proximité trouvent vos disponibilités.',
  'Submit for review': 'Soumettre pour approbation',
  'List {name} in the ClinicFlow directory': 'Inscrire {name} au répertoire ClinicFlow',
  'Only your profile and open times are shared. Never patient names or reasons for visits.':
      'Seuls votre profil et vos plages libres sont partagés. Jamais le nom des patients ni le motif des rendez-vous.',
  'How patients will see you': 'Ce que les patients verront',
  '{n} service bookable online': '{n} service réservable en ligne',
  '{n} services bookable online': '{n} services réservables en ligne',
  'Submitting sends your clinic to ClinicFlow for a quick check of its name, address and phone, usually within one business day.':
      'La soumission envoie votre clinique à ClinicFlow pour une vérification rapide du nom, de l’adresse et du téléphone, habituellement en un jour ouvrable.',
  'Once it’s approved, patients can book you and find you in the directory. Your team can use the calendar meanwhile.':
      'Une fois la clinique approuvée, les patients pourront réserver et vous trouver dans le répertoire. Votre équipe peut utiliser le calendrier d’ici là.',
  'Once it’s approved, patients can book you through your link. Your team can use the calendar meanwhile.':
      'Une fois la clinique approuvée, les patients pourront réserver au moyen de votre lien. Votre équipe peut utiliser le calendrier d’ici là.',

  // ---- Services & clinicians page (pages/clinic.dart)
  'Services & clinicians': 'Services et cliniciens',
  'Add a clinician first.': 'Ajoutez d’abord un clinicien.',
  'The end must be after the start.': 'La fin doit être après le début.',
  '{type} added for {name}': '{type} ajouté pour {name}',
  '{type} added. {n} booked visit is still in that time; move or cancel it.':
      '{type} ajouté. {n} rendez-vous réservé tombe encore dans cette plage : déplacez-le ou annulez-le.',
  '{type} added. {n} booked visits are still in that time; move or cancel them.':
      '{type} ajouté. {n} rendez-vous réservés tombent encore dans cette plage : déplacez-les ou annulez-les.',
  'Time off and breaks': 'Congés et pauses',
  'Shown as unavailable on the calendar. Never bookable online.': 'Affichés comme indisponibles au calendrier. Jamais réservables en ligne.',
  'Type': 'Type',
  'When': 'Quand',
  'No time off or breaks yet.': 'Aucun congé ni aucune pause pour l’instant.',
  'Every day': 'Tous les jours',
  'all day': 'toute la journée',
  'Remove': 'Retirer',
  '{type} removed': '{type} retiré',
  'All day': 'Toute la journée',
  'From': 'De',
  'Until the end of': 'Jusqu’à la fin de',
  'Add': 'Ajouter',
  'Unavailable time types': 'Types d’indisponibilité',
  'Applies to': 'S’applique à',
  'On the calendar': 'Au calendrier',
  'New type': 'Nouveau type',
  'e.g. Team meeting': 'p. ex. Réunion d’équipe',
  'Add type': 'Ajouter le type',
  'Name the type first': 'Nommez d’abord le type',
  '{type} added': '{type} ajouté',

  // ---- unavailable time types (defaultBlockTypes; display only)
  'Break': 'Pause',
  'Not in': 'Hors horaire',
  'Admin time': 'Temps administratif',
  'Vacation': 'Vacances',
  'Statutory holiday': 'Jour férié',
  'Each clinician': 'Chaque clinicien',
  'Whole clinic': 'Toute la clinique',
};
