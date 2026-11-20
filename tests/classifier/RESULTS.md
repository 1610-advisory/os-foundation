Leak classifier bench on 50 made-up notes. Local Ollama only. No new model was pulled.
Hold means the label is not clean and the score is at least the threshold.
Target: hold every person note and every fee note, and false-hold at most 2 of 20 clean notes.
Both gemma4:31b and qwen3.6:35b hit that target at 0.5, 0.7, and 0.9.
Neither model missed a file. False holds on clean notes: none. Exact label recall: 50/50 for both.
Lowest score in the run was 0.95, so the three thresholds did not split the set.
gemma4:31b took 10.0 seconds a note. qwen3.6:35b took 1.8 seconds a note. Machine: Apple M2 Max.
Thinking was off. With thinking on, a short reply comes back empty and the gate cannot score.
Recommendation: qwen3.6:35b at threshold 0.9. It is the faster model, and 0.9 still holds every leak here.
gemma4:31b at 0.9 is a backup if qwen is not loaded. Same accuracy on this set, about five times slower.

# Leak classifier results

Local Ollama only (`format: json`, `think: false`, temperature 0). A hold is a label other than clean with score at or above the threshold. Recall is exact label match. A miss is a leak note that was not held. Warmup is not in the seconds-per-note figure. Raw replies are in `raw/`.

## gemma4:31b

Seconds per note: 10.0 (n=50).

| Threshold | Clean false holds | Fee held | Person held | Candid held | Other-client held | Fee+person misses |
| --- | --- | --- | --- | --- | --- | --- |
| 0.5 | 0/20 | 8/8 (100%) | 10/10 (100%) | 7/7 (100%) | 5/5 (100%) | 0 |
| 0.7 | 0/20 | 8/8 (100%) | 10/10 (100%) | 7/7 (100%) | 5/5 (100%) | 0 |
| 0.9 | 0/20 | 8/8 (100%) | 10/10 (100%) | 7/7 (100%) | 5/5 (100%) | 0 |

Exact-label recall:

| Class | Recall | Wrong labels |
| --- | --- | --- |
| clean | 20/20 (100%) | - |
| fee | 8/8 (100%) | - |
| candid | 7/7 (100%) | - |
| other-client | 5/5 (100%) | - |
| person | 10/10 (100%) | - |

Misses (not held) by file:

- 0.5: none
- 0.7: none
- 0.9: none

False holds on clean notes:

- 0.5: none
- 0.7: none
- 0.9: none

Label mismatches (held or not):

- none

## qwen3.6:35b

Seconds per note: 1.8 (n=50).

| Threshold | Clean false holds | Fee held | Person held | Candid held | Other-client held | Fee+person misses |
| --- | --- | --- | --- | --- | --- | --- |
| 0.5 | 0/20 | 8/8 (100%) | 10/10 (100%) | 7/7 (100%) | 5/5 (100%) | 0 |
| 0.7 | 0/20 | 8/8 (100%) | 10/10 (100%) | 7/7 (100%) | 5/5 (100%) | 0 |
| 0.9 | 0/20 | 8/8 (100%) | 10/10 (100%) | 7/7 (100%) | 5/5 (100%) | 0 |

Exact-label recall:

| Class | Recall | Wrong labels |
| --- | --- | --- |
| clean | 20/20 (100%) | - |
| fee | 8/8 (100%) | - |
| candid | 7/7 (100%) | - |
| other-client | 5/5 (100%) | - |
| person | 10/10 (100%) | - |

Misses (not held) by file:

- 0.5: none
- 0.7: none
- 0.9: none

False holds on clean notes:

- 0.5: none
- 0.7: none
- 0.9: none

Label mismatches (held or not):

- none
