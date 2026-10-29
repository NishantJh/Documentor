from homelab_docs.diffing import diff_values


def test_nested_diff_added_removed_changed():
    before = {"net": {"dns": "1.1.1.1", "old": True}, "items": [1]}
    after = {"net": {"dns": "192.168.1.1", "new": True}, "items": [1, 2]}
    changes = diff_values(before, after)
    assert {item["path"] for item in changes} == {"$.net.old", "$.net.new", "$.net.dns", "$.items"}


def test_identical_state_has_no_diff():
    assert diff_values({"a": 1}, {"a": 1}) == []
