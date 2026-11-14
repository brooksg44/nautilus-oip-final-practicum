// Pilot Light - a panel indicator lamp: lit while its tag is true. One lens colour, chosen by a param.
definePart({
  params: {
    text: { type: 'string', default: 'LAMP', label: 'Legend', desc: 'Text on the legend plate above the lens.' },
    color: { type: 'enum', default: 'green', label: 'Lens colour', options: [
      { value: 'red', label: 'Red' }, { value: 'yellow', label: 'Yellow' }, { value: 'green', label: 'Green' },
      { value: 'white', label: 'White' }, { value: 'blue', label: 'Blue' }] },
    tag: { type: 'tag', dir: 'in', stType: 'BOOL', default: '', label: 'Lamp tag (lit while true)', group: 'Comms', desc: 'The program output that lights the lamp.' },
  },
  step(ctx) {
    const on = ctx.params.tag ? ctx.readTag(ctx.params.tag) : false
    for (const c of ['red', 'yellow', 'green', 'white', 'blue']) ctx.lamps['lens_' + c] = on && ctx.params.color === c
  },
})
