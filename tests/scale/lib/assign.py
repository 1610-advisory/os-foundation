"""Fixed-seed spread of users over areas.

Most users are in one area. Some are in two. Some are in three.
The same seed always gives the same spread.
"""

from __future__ import annotations

import random

from paths import SEED, area_name, user_name


def assignments(users: int, areas: int, seed: int = SEED) -> dict[str, tuple[str, ...]]:
    if users < 1 or areas < 1:
        raise ValueError("users and areas must be at least 1")
    if areas < 3 and users > 0:
        # A user in three areas needs at least three areas.
        pass
    rng = random.Random(seed)
    out: dict[str, tuple[str, ...]] = {}
    span = areas
    for index in range(1, users + 1):
        roll = rng.random()
        if roll < 0.80:
            count = 1
        elif roll < 0.95:
            count = 2
        else:
            count = 3
        count = min(count, span)
        chosen = rng.sample(range(1, span + 1), count)
        out[user_name(index)] = tuple(area_name(n) for n in sorted(chosen))
    return out


def area_counts(rows: dict[str, tuple[str, ...]]) -> dict[int, int]:
    counts = {1: 0, 2: 0, 3: 0}
    for repos in rows.values():
        counts[len(repos)] = counts.get(len(repos), 0) + 1
    return counts


def denial_sample(
    rows: dict[str, tuple[str, ...]],
    areas: int,
    pairs: int,
    seed: int = SEED,
) -> list[dict[str, object]]:
    """Half the pairs are allowed. Half are not. Fixed seed. No duplicates."""
    if pairs < 2 or pairs % 2 != 0:
        raise ValueError("pairs must be even and at least 2")
    each = pairs // 2
    rng = random.Random(seed + 1)
    users = list(rows)
    if not users:
        raise ValueError("no users")
    area_names = [area_name(n) for n in range(1, areas + 1)]
    allowed: list[dict[str, object]] = []
    denied: list[dict[str, object]] = []
    seen: set[tuple[str, str]] = set()
    guard = 0
    limit = pairs * 1000
    while (len(allowed) < each or len(denied) < each) and guard < limit:
        guard += 1
        user = users[rng.randrange(len(users))]
        member = set(rows[user])
        if len(allowed) < each and member:
            repo = rng.choice(tuple(member))
            key = (user, repo)
            if key not in seen:
                seen.add(key)
                allowed.append({"user": user, "repo": repo, "allow": True})
            continue
        outsiders = [name for name in area_names if name not in member]
        if len(denied) < each and outsiders:
            repo = outsiders[rng.randrange(len(outsiders))]
            key = (user, repo)
            if key not in seen:
                seen.add(key)
                denied.append({"user": user, "repo": repo, "allow": False})
    if len(allowed) < each or len(denied) < each:
        raise ValueError("could not build the read-denial sample")
    sample = allowed + denied
    rng.shuffle(sample)
    return sample


def push_users(rows: dict[str, tuple[str, ...]], count: int, seed: int = SEED) -> list[str]:
    if count < 1:
        raise ValueError("count must be at least 1")
    if count > len(rows):
        raise ValueError("count is larger than the bootstrapped users")
    rng = random.Random(seed + 7)
    names = list(rows)
    rng.shuffle(names)
    return names[:count]


def schedule(
    names: list[str],
    rows: dict[str, tuple[str, ...]],
    window_min: float,
    factor: float,
    seed: int = SEED,
) -> list[dict[str, object]]:
    if window_min <= 0 or factor <= 0:
        raise ValueError("window and factor must be positive")
    rng = random.Random(seed + 11)
    jobs = []
    for name in names:
        offset_min = rng.random() * window_min
        jobs.append(
            {
                "user": name,
                "repos": list(rows[name]),
                "offset_min": offset_min,
                "wall_s": offset_min * 60.0 / factor,
            }
        )
    jobs.sort(key=lambda job: float(job["wall_s"]))
    return jobs
