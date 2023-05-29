namespace MX
{
    MX::MapInfo@ preloadedMap;
    bool isLoadingPreload = false;

    void PreloadRandomMap()
    {
        isLoadingPreload = true;
        string URL = CreateQueryURL();
        Json::Value res;
        try {
            res = API::GetAsync(URL)["results"][0];
        } catch {
            Log::Error("ManiaExchange API returned an error, retrying...");
            PreloadRandomMap();
            return;
        }
        Log::Trace("PreloadRandomMapRes: "+Json::Write(res));

        Json::Value playedAt = Json::Object();
        Time::Info date = Time::Parse();
        playedAt["Year"] = date.Year;
        playedAt["Month"] = date.Month;
        playedAt["Day"] = date.Day;
        playedAt["Hour"] = date.Hour;
        playedAt["Minute"] = date.Minute;
        playedAt["Second"] = date.Second;
        res["PlayedAt"] = playedAt;

        MX::MapInfo@ map = MX::MapInfo(res);

        if (map is null){
            Log::Warn("Map is null, retrying...");
            PreloadRandomMap();
            return;
        }

        if (!PluginSettings::UseLengthChecksInRequests) {
            if ((RMC::IsRunning || RMC::IsStarting) && !PluginSettings::CustomRules) {
                if (map.AuthorTime >= 180000) {
                    Log::Warn("Map is too long, retrying...");
                    PreloadRandomMap();
                    return;
                }
            } else if (PluginSettings::MapLength != "Anything") {
                int requiredLength = PluginSettings::SearchingMapLengthsMilliseconds[PluginSettings::SearchingMapLengths.Find(PluginSettings::MapLength)];
                switch (PluginSettings::SearchingMapLengthOperators.Find(PluginSettings::MapLengthOperator)) {
                    case 0:  // exact is prorbably a bit too strict so we'll allow a 5 second difference
                        if (requiredLength == 1e30) {
                            if (map.AuthorTime <= 300000+10000) {
                                Log::Warn("Map is too short, retrying...");
                                PreloadRandomMap();
                                return;
                            } else {
                                break;
                            }
                        } else if ((map.AuthorTime < requiredLength-5000) || (map.AuthorTime > requiredLength+5000)) {
                            Log::Warn("Map is not the correct length, retrying...");
                            PreloadRandomMap();
                            return;
                        }
                        break;
                    
                    case 1:
                        if (requiredLength == 1e30) {
                            if (map.AuthorTime > 300000) {
                                Log::Warn("Map is too long, retrying...");
                                PreloadRandomMap();
                                return;
                            } else {
                                break;
                            }
                        } else if (!(map.AuthorTime < requiredLength)) {
                            Log::Warn("Map is not the correct length, retrying...");
                            PreloadRandomMap();
                            return;
                        }
                        break;
                    
                    case 2:
                        if (requiredLength == 1e30) {
                            if (map.AuthorTime < 300000+10000) {
                                Log::Warn("Map is too short, retrying...");
                                PreloadRandomMap();
                                return;
                            } else {
                                break;
                            }
                        } else if (!(map.AuthorTime > requiredLength)) {
                            Log::Warn("Map is not the correct length, retrying...");
                            PreloadRandomMap();
                            return;
                        }
                        break;
                     
                    case 3:
                        if (requiredLength == 1e30) {
                            // everything is shorter than long, do nothing
                        } else if (!(map.AuthorTime <= requiredLength)) {
                            Log::Warn("Map is not the correct length, retrying...");
                            PreloadRandomMap();
                            return;
                        }
                        break;

                    case 4:
                        if (requiredLength == 1e30) {
                            if (map.AuthorTime <= 300000) {
                                Log::Warn("Map is too long, retrying...");
                                PreloadRandomMap();
                                return;
                            } else {
                                break;
                            }
                        } else if (!(map.AuthorTime >= requiredLength)) {
                            Log::Warn("Map is not the correct length, retrying...");
                            PreloadRandomMap();
                            return;
                        }
                        break;
                }
            }
        }

        isLoadingPreload = false;
        @preloadedMap = map;
    }

    void LoadRandomMap()
    {
        try
        {
            if (TM::CurrentTitlePack() == "") {
                Log::Warn("Please load a title pack first.", true);
                return;
            }
            RandomMapIsLoading = true;
            if (preloadedMap is null && !isLoadingPreload) PreloadRandomMap();
            while (isLoadingPreload) yield();
            MX::MapInfo@ map = preloadedMap;
            @preloadedMap = null;

            Log::LoadingMapNotification(map);

            DataManager::SaveMapToRecentlyPlayed(map);
            RandomMapIsLoading = false;
            if (PluginSettings::closeOverlayOnMapLoaded) UI::HideOverlay();

#if TMNEXT
            TM::ClosePauseMenu();
#endif

            CTrackMania@ app = cast<CTrackMania>(GetApp());
            app.BackToMainMenu(); // If we're on a map, go back to the main menu else we'll get stuck on the current map
            while(!app.ManiaTitleControlScriptAPI.IsReady) {
                yield(); // Wait until the ManiaTitleControlScriptAPI is ready for loading the next map
            }

#if DEPENDENCY_CHAOSMODE
            if (ChaosMode::IsInRMCMode()) {
                Log::Trace("Loading map in Chaos Mode");
                app.ManiaTitleControlScriptAPI.PlayMap("https://"+MX_URL+"/maps/download/"+map.TrackID, "TrackMania/ChaosModeRMC", "");
            } else
#endif
            app.ManiaTitleControlScriptAPI.PlayMap("https://"+MX_URL+"/maps/download/"+map.TrackID, "", "");
        }
        catch
        {
            Log::Warn("Error while loading map ");
            Log::Error(MX_NAME + " API is not responding, it might be down.", true);
            APIDown = true;
            RandomMapIsLoading = false;
        }
    }

    string CreateQueryURL()
    {
        string url = "https://"+MX_URL+"/mapsearch2/search?api=on&random=1";

        if ((RMC::IsRunning || RMC::IsStarting) && !PluginSettings::CustomRules)
        {
            url += "&etags="+RMC::config.etags;
            if (PluginSettings::UseLengthChecksInRequests) {
                url += "&lengthop="+RMC::config.lengthop;
                url += "&length="+RMC::config.length;
            }
        }
        else
        {
            if (PluginSettings::UseLengthChecksInRequests) {
                if (PluginSettings::MapLengthOperator != "Exacts"){
                    url += "&lengthop=" + PluginSettings::SearchingMapLengthOperators.Find(PluginSettings::MapLengthOperator);
                }
                if (PluginSettings::MapLength != "Anything"){
                    url += "&length=" + (PluginSettings::SearchingMapLengths.Find(PluginSettings::MapLength)-1);
                }
            }
            if (!PluginSettings::MapTagsArr.IsEmpty()){
                url += "&tags=" + PluginSettings::MapTags;
            }
            if (!PluginSettings::ExcludeMapTagsArr.IsEmpty()){
                url += "&etags=" + PluginSettings::ExcludeMapTags;
            }
            if (PluginSettings::TagInclusiveSearch){
                url += "&tagsinc=1";
            }
            if (PluginSettings::Difficulty != "Anything"){
                url += "&difficulty=" + (PluginSettings::SearchingDifficultys.Find(PluginSettings::Difficulty)-1);
            }
        }

#if TMNEXT
            // prevent loading CharacterPilot maps
            url += "&vehicles=1";
#elif MP4
            // Fetch in the correct titlepack
            if (TM::CurrentTitlePack() == "TMAll") {
                url += "&tpack=" + TM::CurrentTitlePack()+"&tpack=TMCanyon&tpack=TMValley&tpack=TMStadium&tpack=TMLagoon";
            } else {
                url += "&tpack=" + TM::CurrentTitlePack();
            }
#endif

        // prevent loading non-Race maps (Royal, flagrush etc...)
        url += "&mtype="+SUPPORTED_MAP_TYPE;

        return url;
    }
}