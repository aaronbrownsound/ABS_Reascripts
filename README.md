# ABS_Reascripts
Aaron Brown Sound Reaper Scripts. Mix of utility, and functional scripts to enhance sound design and post workflows.
Note, I did use tool assistance to speed up the creation of these scripts, and I'm new to sharing scripts externally.
Use with caution and please report issues so I can fix these up for others to enjoy.

ABS_SoundDesign_Folderize_NVKParent_5Child_VCAChildrenInline.lua
My quick method of adding new FX tracks with children for NVK workflows. It auto adds new parent tracks with a VCA, and 5 new tracks for sound design. It also auto renames the FX_A tracks in consecutive order so if FX_G exists it names the new one FH_H.

ABS_SoundDesign_RemoveEmptyChildrenInAllFolders_Configs.lua
This removes empty tracks in all folders with extra config options.

ABS_SoundDesign_RemoveEmptyChildrenInSelectedFolders_Configs.lua
Remove empty tracks that are children within a selected folder. Quick way to clean up unused tracks in a design session under a single parent.
This has config options to help remove empty tracks from busy sessions. Useful before you save or archive a session. 

ABS_SoundDesign_RemoveEmptyTracks.lua
This removes empty tracks everywhere, including outside of having parent folders. It has config options to help remove empty tracks from busy sessions. Useful before you save or archive a session. 

ABS_SoundDesign_Whoosh_8CH_Input.lua
Track template of Carlye Nyte's cool 8 track whoosh hack. Will require you to set up differently and point to whoosh, save the track template, then relink it. Maybe not useful for others.

ABS_Tracks_InsertTemplate_Quad_NVK.lua
Adds a quad template for exporting quad in NVK with channel mapping that auditions correctly while allowing a 4 channel export for game audio quads.

ABS_Utility_GenerateActionFromTrackTemplate.lua
This let's you select a track template, then builds a new action for you to run. This way you can quickly instantiate track templates using actions and even do multiple track templates with other scripted actions.

ABS_Utility_NewVideo_Pinned.lua
Adds a new video track named video and pins it to the top.

ABS_Utility_PinMasterAudioTrackTop.lua
In latest reaper this pins the master audio track to the very top.

ABS_Utility_RemoveBypassedFX.lua
Cleans up sessions clutter of fx that were placed, and are now unused. Too often I put in extra plugins that don't make the cut, but leave them because I am in a flow.

ABS_Utility_VideoProcessor_NameAfterItems.lua
Adds video processor to all selected videos, names them after the item name with clear legibility. Useful to adding text to lots of captures for sending to other people with details.

SCHAPPS_Template_Radium_Multichannel.lua
An action that adds Stephen Schapps radium multichannel track template.
