#!/bin/bash
set -o errexit

FORMULA=nicholasdille/tap/dockerd

BOTTLES=$(brew ruby <<EOF
PREFIX = "/home/linuxbrew/.linuxbrew/Homebrew/Library/Taps"

done = []

queue = []
queue.push("${FORMULA}")

while queue.count > 0 do
    formula = queue.pop
    if done.include?(formula)
        next
    end

    STDERR.puts "Processing formula #{formula}"
    done.push(formula)

    name_parts = formula.split("/")
    if name_parts.count > 1
        tap_path = name_parts[0] + "/homebrew-" + name_parts[1]
        name = name_parts[-1]
    else
        tap_path = "homebrew/homebrew-core"
        name = formula
    end
    STDERR.puts "  name=#{name} tap=#{tap_path} tap_path=#{tap_path}"
    path = Pathname.new(PREFIX + "/" + tap_path + "/Formula/" + name + ".rb")
    STDERR.puts "  path=#{path}"
    spec = :stable

    formula = Formulary::FormulaLoader.new(name, path).get_formula(spec)
    STDERR.puts "  version=#{formula.version} revision=#{formula.revision}"

    if formula.bottle == nil
        odie "ERROR: Unbottled formula #{formula}"
    end
    STDERR.puts "  bottle=#{formula.bottle.name} #{formula.bottle.url}"
    puts formula.bottle.url
    formula.deps.each do |dep|
        if dep.tags.exclude?(:build)
            STDERR.puts "  dependency name=#{dep.name} tags=#{dep.tags}"
            queue.push(dep.name)
        end
    end
end
EOF
)

for BOTTLE in ${BOTTLES}; do
    case "${BOTTLE}" in
        *.tar.gz)
            echo "curl/tar: ${BOTTLE}"
            SUBDIR="$(basename "$(dirname "${BOTTLE}")")"
            curl -sL "${BOTTLE}" | tar "--exclude=${SUBDIR}/[A-Z]*" "--exclude=${SUBDIR}/.*" -tvz --strip-components=1
            ;;
        *)
            echo "oras: ${BOTTLE}"
            ;;
    esac
done