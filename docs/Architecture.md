# Architecture

`YL.Prisoners.LordsGrantInfluence` owns both activation and gameplay policy. `BannerCord` supplies the shared runtime dependency and assembly boundary, but installing BannerCord alone does not enable this mechanic.

The campaign behavior is created only by `LordsGrantInfluenceSubModule`. It scans native Bannerlord prisoner rosters each day and stores no parallel state.
