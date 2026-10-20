"""Patcht MOSS-TTS _sample fuer transformers >= 5.3 (bleibt kompatibel mit 5.0-5.2).

Ab transformers 5.3 schneidet prepare_inputs_for_generation die Eingabe per `next_sequence_length`
zu und zaehlt `cache_position` nicht mehr weiter. Der alte Code uebergab beides nicht passend, das
Modell bekam bei jedem Schritt den kompletten Prompt erneut -> Unsinn, kein EOS, OOM.
"""

import sys
from pathlib import Path

path = Path(sys.argv[1])
src = path.read_text(encoding="utf-8")

old_init = """        model_kwargs = self._get_initial_cache_position(cur_len, input_ids.device, model_kwargs)
"""
new_init = """        # transformers >= 5.3 slices the inputs via `next_sequence_length` and no longer advances
        # `cache_position`; the model then derives positions from the cache itself.
        slice_by_length = "next_sequence_length" in inspect.signature(self.prepare_inputs_for_generation).parameters
        if not slice_by_length:
            model_kwargs = self._get_initial_cache_position(cur_len, input_ids.device, model_kwargs)
        is_first_iteration = True
"""

old_prep = """            model_inputs = self.prepare_inputs_for_generation(input_ids, **model_kwargs)
"""
new_prep = """            if slice_by_length:
                next_sequence_length = None if is_first_iteration or not model_kwargs.get("use_cache", True) else 1
                model_inputs = self.prepare_inputs_for_generation(
                    input_ids,
                    next_sequence_length=next_sequence_length,
                    is_first_iteration=is_first_iteration,
                    **model_kwargs,
                )
                is_first_iteration = False
            else:
                model_inputs = self.prepare_inputs_for_generation(input_ids, **model_kwargs)
"""

old_mask = """        mask_kwargs = {
            "config": self.config,
            "input_embeds": inputs_embeds,
            "attention_mask": attention_mask,
            "cache_position": cache_position,
            "past_key_values": past_key_values,
            "position_ids": position_ids,
        }
"""
new_mask = """        # create_causal_mask renamed `input_embeds` -> `inputs_embeds` (5.3) and dropped
        # `cache_position` (later 5.x); pass only what the installed version accepts.
        mask_params = inspect.signature(create_causal_mask).parameters
        mask_kwargs = {
            "config": self.config,
            "inputs_embeds" if "inputs_embeds" in mask_params else "input_embeds": inputs_embeds,
            "attention_mask": attention_mask,
            "past_key_values": past_key_values,
            "position_ids": position_ids,
        }
        if "cache_position" in mask_params:
            mask_kwargs["cache_position"] = cache_position
"""

for old, new in ((old_init, new_init), (old_prep, new_prep), (old_mask, new_mask)):
    if src.count(old) != 1:
        sys.exit(f"Stelle nicht eindeutig gefunden ({src.count(old)}x): {old.strip()[:60]}")
    src = src.replace(old, new)

if "\nimport inspect\n" not in src:
    src = src.replace("\nimport ", "\nimport inspect\nimport ", 1)

backup = path.with_name(path.name + ".orig")
if not backup.exists():
    backup.write_text(path.read_text(encoding="utf-8"), encoding="utf-8")
path.write_text(src, encoding="utf-8")
print("gepatcht:", path)
