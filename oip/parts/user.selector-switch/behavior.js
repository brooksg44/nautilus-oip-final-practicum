// Selector Switch - a 2-position maintained selector (Factory I/O style): exactly one of its two contacts is
// closed. Use turns it to the other position. Left tag is true in the left position, right tag in the right one.
let right = false
let lastParam
definePart({
  interactive: true,
  useParam: 'right', // the position a run starts in; Use never writes it
  params: {
    leftText: { type: 'string', default: 'MAN', label: 'Left legend' },
    rightText: { type: 'string', default: 'AUTO', label: 'Right legend' },
    right: { type: 'boolean', default: false, label: 'In the right position', group: 'Start state', desc: 'The position a run starts in. Use turns the switch to the other position.' },
    leftTag: { type: 'tag', dir: 'out', stType: 'BOOL', default: '', label: 'Left contact tag (true in the left position)', group: 'Comms' },
    rightTag: { type: 'tag', dir: 'out', stType: 'BOOL', default: '', label: 'Right contact tag (true in the right position)', group: 'Comms' },
  },
  step(ctx) {
    if (ctx.params.right !== lastParam) { right = !!ctx.params.right; lastParam = ctx.params.right }
    if (ctx.used()) right = !right
    ctx.report('right', right)
    ctx.joints.turn = right ? -0.7854 : 0.7854
    if (ctx.params.leftTag) ctx.writeTag(ctx.params.leftTag, !right)
    if (ctx.params.rightTag) ctx.writeTag(ctx.params.rightTag, right)
  },
})
