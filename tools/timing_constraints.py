"""Shared, explicit data/reset constraints for R01 and future P08/P12 studies."""
import argparse
import json
import math
from pathlib import Path

from evidence import ROOT

CONFIG = ROOT / 'experiments/reset-timing/config.json'


def constraints(config, study, scenario, mode):
    """Resolve a named model; an omitted reset bound is never defaulted."""
    if config['schema_version'] != 1 or mode not in config['modes']:
        raise ValueError('Unknown constraint schema or drive mode')
    data, reset = config['studies'][study], config['scenarios'][scenario]
    for key, values in ((('data_min_ns', 'data_max_ns', 'uncertainty_ns'), data),
                        (('reset_min_ns', 'reset_max_ns'), reset),
                        (('period_ns', 'input_transition_ns', 'output_load_ff'), config)):
        for name in key:
            value = values[name]
            if isinstance(value, bool) or not isinstance(value, (int, float)) or not math.isfinite(value) or value < 0:
                raise ValueError('Invalid constraint value: ' + name)
    if config['period_ns'] <= 0 or reset['edge'] not in ('rise', 'fall') or not reset['source']:
        raise ValueError('Invalid clock/reset source model')
    if data['data_min_ns'] > data['data_max_ns'] or reset['reset_min_ns'] > reset['reset_max_ns']:
        raise ValueError('Reversed constraint envelope')
    for key in ('driving_cell', 'driving_pin'):
        if not config[key].replace('_', '').isalnum():
            raise ValueError('Invalid drive identifier')
    return dict(study=study, scenario=scenario, mode=mode, **data, **reset,
                **{k: config[k] for k in ('period_ns', 'input_transition_ns', 'output_load_ff', 'driving_cell', 'driving_pin')})


def render(model):
    phase = ' -clock_fall' if model['edge'] == 'fall' else ''
    lines = [f'# {model["study"]} / {model["scenario"]} / {model["mode"]}; ns/fF; ideal clock',
             f'create_clock -name clk -period {model["period_ns"]} [get_ports clk]',
             f'set_clock_uncertainty {model["uncertainty_ns"]} [get_clocks clk]',
             'set reset [get_ports rst_n]',
             'if {[llength $reset] != 1} {error "R01_RESET_PORT"}',
             'set data_inputs [get_ports -filter {direction == input && name != clk && name != rst_n}]']
    for bound in ('min', 'max'):
        lines += [f'set_input_delay -{bound} -clock clk {model["data_" + bound + "_ns"]} $data_inputs',
                  f'set_output_delay -{bound} -clock clk {model["data_" + bound + "_ns"]} [all_outputs]',
                  f'set_input_delay -{bound} -clock clk{phase} {model["reset_" + bound + "_ns"]} $reset']
    if model['mode'] == 'slew':
        lines += [f'set_input_transition {model["input_transition_ns"]} [all_inputs -no_clocks]']
    else:
        lines += [f'set_driving_cell -lib_cell {model["driving_cell"]} -pin {model["driving_pin"]} [all_inputs -no_clocks]']
    lines += [f'set_load {model["output_load_ff"]} [all_outputs]']
    return '\n'.join(lines) + '\n'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--config', type=Path, default=CONFIG)
    parser.add_argument('--study', required=True)
    parser.add_argument('--scenario', required=True)
    parser.add_argument('--mode', choices=('slew', 'drive'), required=True)
    parser.add_argument('--output', type=Path, required=True)
    args = parser.parse_args()
    model = constraints(json.loads(args.config.read_text()), args.study, args.scenario, args.mode)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(render(model))


if __name__ == '__main__':
    main()
