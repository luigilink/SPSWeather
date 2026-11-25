# SPSWeather.Common - libellés d'affichage (fr-FR).
#
# Mêmes clés que la culture de référence en-US : un test vérifie que les clés et les
# paramètres {0}, {1}... sont identiques. Une clé absente ici s'affiche en anglais.
# Les valeurs sont du texte brut (jamais de HTML). Seul l'affichage est traduit : les valeurs
# des collecteurs, les en-têtes des tableaux de détail et les étiquettes du sujet du mail
# ([ALERT], [WARN], [OK]) restent en anglais volontairement.
# Enregistrer en UTF-8 avec BOM. Dans une valeur, une apostrophe s'écrit '' (deux apostrophes ASCII) :
# PowerShell traite les apostrophes typographiques comme des guillemets et fermerait la chaîne.

@{
    # Culture metadata
    Culture  = 'fr-FR'
    HtmlLang = 'fr'

    # Dashboard: header, donut and run history
    DashboardTitle = 'Tableau de bord SPSWeather'
    FarmLabel      = 'Ferme'
    Generated      = 'Généré le'
    NeedAttention  = '{0} élément(s) à examiner'
    OverallHealth  = 'Santé globale'
    Healthy        = 'sain'
    Percent = '{0} %'
    ShortOk        = 'OK'
    ShortWarn      = 'Avert.'
    ShortFail      = 'Échecs'
    RunHistory     = 'Historique'
    LastRunsMany       = '{0} dernières exécutions'
    LastRunsOne = 'dernière exécution'
    LegendWarning  = 'Avertissement'
    LegendFailure  = 'Échec'
    HoverBar       = 'survolez une barre pour les totaux'
    HistoryDateFormat = 'dd/MM'
    NowSuffix      = ' (maintenant)'
    BarTip         = '{0} : {1} OK / {2} avert. / {3} échec(s)'

    # Dashboard: areas, detail and footer
    HealthByArea = 'Santé par composant'
    Detail       = 'Détail'
    ExpandAll    = 'Tout développer'
    CollapseAll  = 'Tout réduire'
    ViewDetail   = 'Voir le détail'
    PillFailed   = '{0} en échec'
    PillWarning  = '{0} avert.'
    RowAlert     = '{0} alerte(s)'
    RowWarn      = '{0} avert.'
    RowOk        = '{0} OK'
    RowInfo      = '{0} info(s)'
    ExecutedBy   = 'Exécuté par'

    # Weather
    WeatherLabel  = 'Météo'
    WeatherSunny  = 'Ensoleillé'
    WeatherFair   = 'Peu nuageux'
    WeatherCloudy = 'Nuageux'
    WeatherStormy = 'Orageux'

    # Alert email
    ItemCountOne     = '{0} élément'
    ItemCountMany    = '{0} éléments'
    FailureOne       = '{0} échec'
    FailureMany      = '{0} échecs'
    WarningOne       = '{0} avertissement'
    WarningMany      = '{0} avertissements'
    MoreItems        = '+ {0} de plus ({1})'
    MoreSeeDashboard = 'voir le tableau de bord pour la liste complète'
    AllClearTitle    = 'Tout est en ordre.'
    AllClearText     = 'Aucun élément à examiner sur cette ferme.'
    IntroAttention   = '{0} à examiner sur {1}. Le détail complet est dans le tableau de bord.'
    IntroClear       = 'Aucun élément à examiner sur {0}.'
    KpiFailures      = 'Échecs'
    KpiWarnings      = 'Avertissements'
    KpiChecksOk      = 'Contrôles OK'
    OpenDashboard    = 'Ouvrir le tableau de bord complet'
    FooterExecutedBy = 'exécuté par'
    FooterRun        = 'durée'
    CountsSummary    = '{0} OK / {1} avert. / {2} échec(s)'
    FreePercent      = '{0} % d''espace libre'

    # Mail consolidé (toutes les fermes d'un environnement dans un seul message)
    FarmCountOne       = '{0} ferme'
    FarmCountMany      = '{0} fermes'
    FarmStatusAlert    = 'ALERTE'
    FarmStatusWarn     = 'AVERTISSEMENT'
    FarmStatusOk       = 'SAINE'
    FarmStatusDown     = 'INJOIGNABLE'
    FarmHealth         = '{0} sain'
    FarmAttentionTitle = 'Points d''attention'
    UnreachableTitle   = 'La ferme n''a pas pu être interrogée.'
    UnreachableText    = 'Aucun contrôle n''a été exécuté. Voir le journal d''événements SPSWeather (ID 3001).'
    FarmsOfTotalOne    = '{0} ferme sur {1}'
    FarmsOfTotalMany   = '{0} fermes sur {1}'
    IntroFarmsOne      = '{0} nécessite votre attention sur {1}. Le détail complet est dans le tableau de bord de chaque ferme.'
    IntroFarmsMany     = '{0} nécessitent votre attention sur {1}. Le détail complet est dans le tableau de bord de chaque ferme.'
    FooterFarmsQueried = 'fermes interrogées : {0} sur {1}'

    # Functional areas (dashboard cards and email groups)
    Area_FarmUpgrade        = 'Ferme & mise à niveau'
    Area_TrustFarm          = 'Ferme approuvée (REST)'
    Area_Search             = 'Recherche'
    Area_DistributedCache   = 'Cache distribué'
    Area_TimerJobsSolutions = 'Travaux du minuteur & solutions'
    Area_TimerJobs          = 'Travaux du minuteur'
    Area_Solutions          = 'Solutions'
    Area_UserProfiles       = 'Profils utilisateur'
    Area_HealthAnalyzer     = 'Analyseur d''intégrité'
    Area_IIS                = 'IIS'
    Area_System             = 'Système'
    Area_SQL                = 'SQL Server'

    # Section labels (one per report section)
    Section_SPHealthAnalyzer         = 'Analyseur d''intégrité'
    Section_SPUpgradeStatus          = 'État de la mise à niveau'
    Section_SPAPIHttpStatus          = 'Ferme approuvée (REST)'
    Section_SPSSitesHttpStatus       = 'État HTTP des sites'
    Section_SPTimerServiceStatus     = 'Service de minuteur - Instances'
    Section_SPFailedTimerJobs        = 'Travaux du minuteur en échec'
    Section_SPSolutionDeployment     = 'Déploiement des solutions'
    Section_SPSearchLastCrawlStatus  = 'Recherche - Dernière analyse'
    Section_SPSearchCrawlLogs        = 'Recherche - Journaux d''analyse'
    Section_SPSSearchEntTopology     = 'Recherche - Topologie'
    Section_AppFabricStatus          = 'Cache distribué'
    Section_USPAudienceStatus        = 'Audiences de profils utilisateur'
    Section_IISApplicationPoolStatus = 'IIS - Pools d''applications'
    Section_IISWorkerProcessStatus   = 'IIS - Processus de travail'
    Section_IISWebSiteCertStatus     = 'IIS - Certificats SSL'
    Section_SYSEventViewerAppErrors  = 'Système - Erreurs du journal d''événements'
    Section_SYSDiskUsageStatus       = 'Système - Utilisation des disques'
    Section_SYSLastRebootStatus      = 'Système - Dernier redémarrage'
    Section_SYSDOTNETVersion         = 'Système - .NET Framework'
    Section_SPSContentDBStatus       = 'Bases de données de contenu'
    Section_SQLInstanceStatus        = 'SQL - Instances'
    Section_SQLDatabaseStatus        = 'SQL - Bases de données'
    Section_SQLDiskStatus            = 'SQL - Volumes de disque'
    Section_SQLAvailabilityStatus    = 'SQL - Groupes de disponibilité'
    Section_SQLAliasStatus           = 'SQL - Alias'
}
