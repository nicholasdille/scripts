hcloud2null() {
    hcloud volume list -o columns=id | tail -n +2 | xargs -r -n 1 hcloud volume detach
    hcloud volume list -o columns=id | tail -n +2 | xargs -r -n 1 hcloud volume delete
    hcloud server list -o columns=id | tail -n +2 | xargs -r -n 1 hcloud server delete
}