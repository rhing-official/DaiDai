import 'guide_content.dart';

/// 使い方ガイドのフランス語訳（2026-10-17追加、AIによる初稿。公開前にネイティブの
/// 確認を推奨）。用語は`Vocabulary.french`（Duo・Place・Salon・Bibliothèque de profils・Éditeur de profil）に
/// 合わせる。手順の段落数は原文（`guide_content.dart`）と同じにする。
const guideTranslationFr = GuideTranslation(
  topics: {
    'friends': GuideTopicText(
      title: 'Ajouter des amis',
      summary: 'Devenez amis avec un lien d’invitation ou un code QR',
      steps: [
        'Ouvrez « Ajouter des amis » dans l’onglet Profil pour voir votre lien d’invitation et votre code QR. Envoyez-le à quelqu’un, ou laissez la personne le scanner.',
        'Ouvrez le lien d’invitation d’une autre personne ou scannez son code QR pour envoyer une demande d’ami. Dès qu’elle accepte, votre Duo commence.',
        'Si vous collez un lien d’invitation dans un message DaiDai, il s’affiche sous forme de carte de profil.',
      ],
    ),
    'direct-plaza': GuideTopicText(
      title: 'Duo et Place',
      summary: 'Conversations en tête-à-tête et espaces de groupe',
      steps: [
        'Un « Duo » est une conversation privée avec un seul ami. Une « Place » est un espace pour trois personnes ou plus, géré par son propriétaire.',
        'Invitez des personnes sur une Place avec un lien d’invitation. Le propriétaire choisit dans les réglages de la Place si l’adhésion nécessite son approbation.',
        'Les rôles permettent au propriétaire de partager des autorisations de gestion (gérer les salons, créer des liens d’invitation, etc.) avec des membres.',
      ],
    ),
    'rooms': GuideTopicText(
      title: 'Salons',
      summary: 'Séparez les sujets au sein d’une même conversation',
      steps: [
        'Dans un Duo comme dans une Place, vous pouvez ajouter des salons pour séparer les sujets. Au début, il n’y en a qu’un seul.',
        'Pour utiliser plusieurs salons, activez la fonction de salons dans les réglages de la conversation. Vous pourrez alors en ajouter et passer de l’un à l’autre.',
      ],
    ),
    'messages': GuideTopicText(
      title: 'Envoyer des messages',
      summary: 'Texte, photos, fichiers, stickers et mentions',
      steps: [
        'Outre le texte, vous pouvez envoyer jusqu’à 10 photos, vidéos ou fichiers dans un même message.',
        'Pendant que vous écrivez, des stickers suggérés peuvent apparaître au-dessus du champ de saisie.',
        'Tapez « @ » pour mentionner quelqu’un, ou « @everyone » pour notifier tout le groupe.',
        'Vous pouvez répondre à des messages, les épingler, ou en sélectionner plusieurs pour les supprimer. La suppression ne les masque que pour vous ; ils sont supprimés du serveur lorsque tout le monde les a supprimés.',
      ],
    ),
    'notes': GuideTopicText(
      title: 'Notes',
      summary: 'Gardez des notes au sein d’une conversation',
      steps: [
        'Ouvrez « Notes » depuis le menu de la conversation pour écrire du texte, des titres, des listes et des tableaux.',
        'Utilisez « + » pour ajouter des blocs comme des tableaux. Sur téléphone, touchez une cellule pour afficher les poignées de ligne et de colonne ; appuyez longuement pour réorganiser ou sélectionner une plage.',
      ],
    ),
    'calendar': GuideTopicText(
      title: 'Calendrier',
      summary: 'Événements partagés et planification',
      steps: [
        'Ouvrez « Calendrier » depuis le menu de la conversation pour ajouter et partager des événements.',
        'La planification vous permet de proposer des dates et de recueillir les disponibilités de chacun.',
        'Dans Réglages > Compte, vous pouvez activer la synchronisation avec Google Agenda.',
      ],
    ),
    'album': GuideTopicText(
      title: 'Album',
      summary: 'Conservez photos et vidéos par conversation',
      steps: [
        'Ajoutez à l’album les photos et vidéos des messages pour les conserver, même après la durée de conservation des messages.',
        'Ouvrez l’album depuis le menu de la conversation.',
      ],
    ),
    'calls': GuideTopicText(
      title: 'Appels',
      summary: 'Appels vocaux et vidéo',
      steps: [
        'Lancez un appel vocal ou vidéo depuis n’importe quel Duo ou Place.',
        'Pendant un appel, vous pouvez réduire l’écran et continuer tout en consultant autre chose.',
      ],
    ),
    'profile': GuideTopicText(
      title: 'Profil',
      summary:
          'Soignez vos cartes dans la Bibliothèque de profils et l’Éditeur de profil',
      steps: [
        'La Bibliothèque de profils conserve vos icônes, images d’arrière-plan, pseudos et statuts.',
        'Dans l’Éditeur de profil, vous combinez des éléments en cartes de profil. Vous pouvez en créer jusqu’à trois et utiliser des cartes différentes selon la conversation.',
      ],
    ),
    'safety': GuideTopicText(
      title: 'Sécurité et confidentialité',
      summary:
          'Blocage, rupture, protection de la connexion et suppression du compte',
      steps: [
        'Bloquer quelqu’un dans un Duo masque ses messages et ses demandes. La personne n’est pas informée du blocage.',
        'La « rupture » supprime définitivement l’historique d’un Duo, mais uniquement si les deux personnes sont d’accord.',
        'Dans Réglages > Compte, vous pouvez configurer l’authentification à deux facteurs (application d’authentification) et les clés d’accès pour une connexion plus sûre.',
        'Un compte supprimé peut être restauré pendant 30 jours, ou vous pouvez le supprimer immédiatement et définitivement. Si vous êtes propriétaire d’une Place, transférez d’abord la propriété.',
      ],
    ),
    'kiwami': GuideTopicText(
      title: 'Premium',
      summary: 'Un forfait payant qui débloque des fonctions supplémentaires',
      steps: [
        '« Premium » est un forfait payant qui regroupe des extras comme le masquage des accusés de lecture et des polices exclusives. Le masquage des accusés de lecture ne s’applique que tant qu’une personne de la conversation a Premium.',
        'La façon de s’abonner arrive bientôt. Sans Premium, les polices exclusives s’affichent dans la police standard.',
      ],
    ),
  },
);
