# concatenate multiple sessions
# if you have multiple sessions and want to concatenate them into a single recording, you can use this script.
# note will need to change paths
import spikeinterface as si
import spikeinterface.extractors as se
from pathlib import Path

day_folders = sorted(Path("data/spikeglx").iterdir())[:3]  # note only using first three sessions for testing, change to [:] for all sessions
stream_name = "imec0.ap" 

recordings = [se.read_spikeglx(d, stream_name=stream_name) for d in day_folders]
concatenated = si.append_recordings(recordings)

concatenated.save(folder="data/spikeglx/concat_session", format="binary", n_jobs=-1, overwrite = True)