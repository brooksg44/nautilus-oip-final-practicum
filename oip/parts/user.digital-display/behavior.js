// Digital Display - a panel readout of a number the program writes (Factory I/O's Digital Display).
definePart({
  params: {
    text: { type: 'string', default: 'VALUE', label: 'Legend', desc: 'Text on the legend plate above the readout.' },
    decimals: { type: 'number', default: 0, min: 0, max: 3, step: 1, label: 'Decimals', desc: 'Digits shown after the point.' },
    tag: { type: 'tag', dir: 'in', stType: 'INT', default: '', label: 'Value tag (the number shown)', group: 'Comms', desc: 'The program output whose value is shown.' },
  },
  step(ctx) {
    const v = ctx.params.tag ? ctx.readNumber(ctx.params.tag) : 0
    const d = Math.max(0, Math.min(3, Math.round(ctx.params.decimals || 0)))
    ctx.display('value', Number.isFinite(v) ? v.toFixed(d) : '----')
  },
})
