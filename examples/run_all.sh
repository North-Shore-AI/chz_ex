#!/bin/bash
set -e

echo "=== ChzEx Examples ==="
echo

examples=(
  "basic_config.exs name=test value=42"
  "nested_config.exs name=exp model.hidden_dim=256"
  "polymorphic_config.exs name=exp optimizer=sgd optimizer.momentum=0.99"
  "wildcards.exs name=exp ...activation=gelu"
  "references.exs base_dim=512"
  "validation.exs value=50"
  "mungers.exs name=experiment"
  "presets.exs small model.num_heads=4"
  "factory_variants.exs handler=beta handler.message=hello"
  "cli_entrypoint.exs name=myapp --help"
  "help_generation.exs"
  "entrypoint_variants.exs run name=demo count=2"
  "entrypoint_variants.exs methods train project=demo epochs=5"
  "entrypoint_variants.exs nested name=demo count=3"
  "serialization_roundtrip.exs"
  "type_system.exs"
  "advanced_types.exs"
)

for example in "${examples[@]}"; do
  file=$(echo "$example" | cut -d' ' -f1)
  args=$(echo "$example" | cut -s -d' ' -f2-)

  echo "--- Running: $file $args ---"
  mix run "examples/$file" -- $args || true
  echo
done

echo "=== All examples completed ==="
