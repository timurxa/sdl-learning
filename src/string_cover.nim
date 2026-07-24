## Exact compile-time selection of contiguous byte loads.
##
## Objective, in order:
##   1. fewest loads;
##   2. fewest loaded bytes.

import std/bitops

type
  ByteLoad* = object
    offset*: int
    width*: int

  Candidate = object
    load: ByteLoad

  Search = ref object
    candidates: seq[Candidate]
    cover: seq[uint64]       # Candidate-major bitsets.
    pairOrder: seq[int]
    words: int
    pairCount: int
    target: int
    optimizeBytes: bool
    stop: bool
    bestBytes: int
    gains: seq[int]
    topMarks: seq[int]
    topGeneration: int
    widthTopGains: seq[int]
    forbidden: seq[bool]
    states: seq[uint64]      # One unresolved-pair bitset per depth.
    branches: seq[int]       # One candidate scratch slice per depth.
    chosen: seq[int]
    bestChosen: seq[int]
    enforcePrefixIrreducible: bool
    byteLength: int
    maxWidth: int
    intervalMarks: seq[int]
    intervalGeneration: int
    separatorOffsets: seq[int] # Optional pair-major separator CSR.
    separatorItems: seq[int]

const AllowedWidths = [1, 2, 4, 8]

func `<`*(a, b: ByteLoad): bool =
  if a.offset != b.offset:
    a.offset < b.offset
  else:
    a.width < b.width

proc loadValue(s: string; offset, width: int): uint64 {.compileTime.} =
  var value = 0'u64
  var byteIndex = 0
  while byteIndex < width:
    value = value or (uint64(ord(s[offset + byteIndex])) shl
                      (byteIndex shl 3))
    inc byteIndex
  value

proc validateInput(strings: openArray[string]): int {.compileTime.} =
  if strings.len == 0:
    return 0
  result = strings[0].len
  var i = 0
  while i < strings.len:
    if strings[i].len != result:
      raise newException(ValueError,
        "chooseByteLoads requires one equal-length string partition")
    var j = 0
    while j < i:
      if strings[j] == strings[i]:
        raise newException(ValueError,
          "chooseByteLoads requires distinct strings")
      inc j
    inc i

template bitIsSet(bits: seq[uint64]; base, bit: int): bool =
  (bits[base + (bit shr 6)] and (1'u64 shl (bit and 63))) != 0

proc coverageEqual(cover: seq[uint64]; words, a, b: int): bool
    {.compileTime.} =
  let aBase = a * words
  let bBase = b * words
  var word = 0
  while word < words:
    if cover[aBase + word] != cover[bBase + word]:
      return false
    inc word
  true

proc coverageSubset(cover: seq[uint64]; words, subset, superset: int): bool
    {.compileTime.} =
  let subBase = subset * words
  let superBase = superset * words
  var word = 0
  while word < words:
    if (cover[subBase + word] and not cover[superBase + word]) != 0:
      return false
    inc word
  true

proc avalancheHash(value: uint64): uint64 {.compileTime.} =
  var mixed = value
  mixed = (mixed xor (mixed shr 30)) * 0xBF58476D1CE4E5B9'u64
  mixed = (mixed xor (mixed shr 27)) * 0x94D049BB133111EB'u64
  mixed xor (mixed shr 31)

proc coverageHash(cover: seq[uint64]; words, candidate: int): uint64
    {.compileTime.} =
  result = 1469598103934665603'u64
  let base = candidate * words
  var word = 0
  while word < words:
    result = (result xor cover[base + word]) * 1099511628211'u64
    inc word
  result = avalancheHash(result)

proc uniqueLoadSignatures(strings: openArray[string];
                          loads: openArray[ByteLoad]): bool
    {.compileTime.} =
  if strings.len <= 1:
    return true
  let byteLength = strings[0].len
  var i = 0
  while i < strings.len:
    if strings[i].len != byteLength:
      return false
    inc i
  i = 0
  while i < loads.len:
    if loads[i].offset < 0 or loads[i].width notin AllowedWidths or
        loads[i].offset + loads[i].width > byteLength:
      return false
    inc i

  var signatures = newSeq[uint64](strings.len * loads.len)
  var stringIndex = 0
  while stringIndex < strings.len:
    i = 0
    while i < loads.len:
      signatures[stringIndex * loads.len + i] =
        loadValue(strings[stringIndex], loads[i].offset, loads[i].width)
      inc i
    inc stringIndex

  var tableSize = 1
  while tableSize < strings.len * 2:
    tableSize = tableSize shl 1
  var slots = newSeq[int](tableSize)
  var hashes = newSeq[uint64](strings.len)
  stringIndex = 0
  while stringIndex < strings.len:
    var signatureHash = 1469598103934665603'u64
    i = 0
    while i < loads.len:
      signatureHash =
        (signatureHash xor signatures[stringIndex * loads.len + i]) *
        1099511628211'u64
      inc i
    signatureHash = avalancheHash(signatureHash)
    hashes[stringIndex] = signatureHash
    var slot = int(signatureHash and uint64(tableSize - 1))
    while slots[slot] != 0:
      let prior = slots[slot] - 1
      if hashes[prior] == signatureHash:
        var equal = true
        i = 0
        while i < loads.len:
          if signatures[prior * loads.len + i] !=
              signatures[stringIndex * loads.len + i]:
            equal = false
            break
          inc i
        if equal:
          return false
      slot = (slot + 1) and (tableSize - 1)
    slots[slot] = stringIndex + 1
    inc stringIndex
  true

proc findSingleLoad(strings: openArray[string]; byteLength: int;
                    found: var ByteLoad): bool {.compileTime.} =
  var tableSize = 1
  while tableSize < strings.len * 2:
    tableSize = tableSize shl 1
  var stamps = newSeq[int](tableSize)
  var keys = newSeq[uint64](tableSize)
  var generation = 0
  var widthIndex = 0
  while widthIndex < AllowedWidths.len:
    let width = AllowedWidths[widthIndex]
    if width <= byteLength:
      var offset = 0
      while offset <= byteLength - width:
        inc generation
        var unique = true
        var stringIndex = 0
        while stringIndex < strings.len:
          let value = loadValue(strings[stringIndex], offset, width)
          var slot = int(avalancheHash(value) and uint64(tableSize - 1))
          while stamps[slot] == generation:
            if keys[slot] == value:
              unique = false
              break
            slot = (slot + 1) and (tableSize - 1)
          if not unique:
            break
          stamps[slot] = generation
          keys[slot] = value
          inc stringIndex
        if unique:
          found = ByteLoad(offset: offset, width: width)
          return true
        inc offset
    inc widthIndex
  false

proc compressCandidates(candidates: var seq[Candidate];
                        cover: var seq[uint64];
                        words: int) {.compileTime.} =
  let count = candidates.len
  if count == 0:
    return

  var alive = newSeq[bool](count)
  var i = 0
  while i < count:
    let base = i * words
    var useful = false
    var word = 0
    while word < words:
      if cover[base + word] != 0:
        useful = true
        break
      inc word
    alive[i] = useful
    inc i

  # Candidate generation is ordered by width, then offset. Exact open
  # addressing makes equivalent-cover removal expected-linear while full
  # equality checks make hash collisions harmless.
  var tableSize = 1
  while tableSize < count * 2:
    tableSize = tableSize shl 1
  var equivalentSlots = newSeq[int](tableSize)
  i = 0
  while i < count:
    if alive[i]:
      var slot = int(coverageHash(cover, words, i) and
                     uint64(tableSize - 1))
      while equivalentSlots[slot] != 0:
        let earlier = equivalentSlots[slot] - 1
        if coverageEqual(cover, words, earlier, i):
          alive[i] = false
          break
        slot = (slot + 1) and (tableSize - 1)
      if alive[i]:
        equivalentSlots[slot] = i + 1
    inc i

  # If A's covered pairs are a subset of B's and B is no wider, every
  # solution using A can replace it with B without worsening either objective.
  var aliveCount = 0
  i = 0
  while i < count:
    if alive[i]:
      inc aliveCount
    inc i
  const DominanceWorkLimit = 250_000
  if aliveCount * aliveCount * words <= DominanceWorkLimit:
    i = 0
    while i < count:
      if alive[i]:
        var dominator = 0
        while dominator < count:
          if dominator != i and alive[dominator] and
              candidates[dominator].load.width <=
                candidates[i].load.width and
              coverageSubset(cover, words, i, dominator):
            alive[i] = false
            break
          inc dominator
      inc i

  var kept = 0
  i = 0
  while i < count:
    if alive[i]:
      inc kept
    inc i

  var newCandidates = newSeq[Candidate](kept)
  var newCover = newSeq[uint64](kept * words)
  var dst = 0
  i = 0
  while i < count:
    if alive[i]:
      newCandidates[dst] = candidates[i]
      var word = 0
      while word < words:
        newCover[dst * words + word] = cover[i * words + word]
        inc word
      inc dst
    inc i
  candidates = newCandidates
  cover = newCover

proc reducePairConstraints(candidates: seq[Candidate];
                           cover: var seq[uint64];
                           pairCount: var int;
                           words: var int): bool {.compileTime.} =
  # Row subsumption is quadratic in pair count. Gate it where its kernel
  # usually costs less than the search it saves.
  if pairCount <= 1 or pairCount > 512 or candidates.len == 0:
    return

  let candidateWords = (candidates.len + 63) shr 6
  const PairReductionWorkLimit = 2_000_000
  if pairCount * pairCount * candidateWords > PairReductionWorkLimit:
    return
  var separators = newSeq[uint64](pairCount * candidateWords)
  var pair = 0
  while pair < pairCount:
    var candidate = 0
    while candidate < candidates.len:
      if bitIsSet(cover, candidate * words, pair):
        separators[pair * candidateWords + (candidate shr 6)] =
          separators[pair * candidateWords + (candidate shr 6)] or
          (1'u64 shl (candidate and 63))
      inc candidate
    inc pair

  var alive = newSeq[bool](pairCount)
  pair = 0
  while pair < pairCount:
    alive[pair] = true
    inc pair

  # A constraint with separator superset P is implied by harder constraint Q
  # when Sep(Q) is a subset of Sep(P).
  pair = 0
  while pair < pairCount:
    var harder = 0
    while harder < pairCount:
      if harder != pair:
        var subset = true
        var equal = true
        var word = 0
        while word < candidateWords:
          let pWord = separators[pair * candidateWords + word]
          let qWord = separators[harder * candidateWords + word]
          if (qWord and not pWord) != 0:
            subset = false
            break
          if pWord != qWord:
            equal = false
          inc word
        if subset and (not equal or harder < pair):
          alive[pair] = false
          break
      inc harder
    inc pair

  var kept = 0
  pair = 0
  while pair < pairCount:
    if alive[pair]:
      inc kept
    inc pair
  if kept == pairCount:
    return

  let newWords = (kept + 63) shr 6
  var newCover = newSeq[uint64](candidates.len * newWords)
  var newPair = 0
  pair = 0
  while pair < pairCount:
    if alive[pair]:
      var candidate = 0
      while candidate < candidates.len:
        if bitIsSet(cover, candidate * words, pair):
          newCover[candidate * newWords + (newPair shr 6)] =
            newCover[candidate * newWords + (newPair shr 6)] or
            (1'u64 shl (newPair and 63))
        inc candidate
      inc newPair
    inc pair
  pairCount = kept
  words = newWords
  cover = newCover
  true

proc fillGains(search: Search; stateBase, gainBase: int) {.compileTime.} =
  var candidate = 0
  while candidate < search.candidates.len:
    if search.forbidden[candidate]:
      search.gains[gainBase + candidate] = 0
    else:
      let coverBase = candidate * search.words
      var gain = 0
      var word = 0
      while word < search.words:
        gain += countSetBits(
          search.states[stateBase + word] and
          search.cover[coverBase + word])
        inc word
      search.gains[gainBase + candidate] = gain
    inc candidate

proc countLowerBound(search: Search; unresolved, budget, gainBase: int): int
    {.compileTime.} =
  if unresolved == 0:
    return 0
  inc search.topGeneration
  let generation = search.topGeneration
  var covered = 0
  while result < budget and covered < unresolved:
    var best = -1
    var bestGain = 0
    var candidate = 0
    while candidate < search.candidates.len:
      if search.topMarks[candidate] != generation and
          search.gains[gainBase + candidate] > bestGain:
        best = candidate
        bestGain = search.gains[gainBase + candidate]
      inc candidate
    if best < 0:
      return budget + 1
    search.topMarks[best] = generation
    covered += bestGain
    inc result
  if covered < unresolved:
    budget + 1
  else:
    result

proc gainWidthLowerBound(search: Search; unresolved, needed,
                         gainBase: int): int {.compileTime.} =
  ## For each width, retain its `needed` largest current gains. Enumerate all
  ## width-count allocations. Additive gains ignore overlap, so any allocation
  ## whose optimistic sum is below `unresolved` is impossible.
  var i = 0
  while i < search.widthTopGains.len:
    search.widthTopGains[i] = 0
    inc i

  var candidate = 0
  while candidate < search.candidates.len:
    let gain = search.gains[gainBase + candidate]
    if gain > 0:
      let widthClass =
        case search.candidates[candidate].load.width
        of 1: 0
        of 2: 1
        of 4: 2
        else: 3
      let base = widthClass * needed
      var position = 0
      while position < needed and
          search.widthTopGains[base + position] >= gain:
        inc position
      if position < needed:
        var move = needed - 1
        while move > position:
          search.widthTopGains[base + move] =
            search.widthTopGains[base + move - 1]
          dec move
        search.widthTopGains[base + position] = gain
    inc candidate

  # Convert each width slice to prefix sums in place.
  var widthClass = 0
  while widthClass < 4:
    let base = widthClass * needed
    i = 1
    while i < needed:
      search.widthTopGains[base + i] +=
        search.widthTopGains[base + i - 1]
      inc i
    inc widthClass

  result = high(int)
  var ones = 0
  while ones <= needed:
    var twos = 0
    while twos <= needed - ones:
      var fours = 0
      while fours <= needed - ones - twos:
        let eights = needed - ones - twos - fours
        var optimistic = 0
        if ones > 0:
          optimistic += search.widthTopGains[ones - 1]
        if twos > 0:
          optimistic += search.widthTopGains[needed + twos - 1]
        if fours > 0:
          optimistic += search.widthTopGains[2 * needed + fours - 1]
        if eights > 0:
          optimistic += search.widthTopGains[3 * needed + eights - 1]
        if optimistic >= unresolved:
          let bytes = ones + 2 * twos + 4 * fours + 8 * eights
          if bytes < result:
            result = bytes
        inc fours
      inc twos
    inc ones

proc betterBranch(search: Search; a, b, gainBase: int): bool
    {.compileTime.} =
  if search.gains[gainBase + a] != search.gains[gainBase + b]:
    search.gains[gainBase + a] > search.gains[gainBase + b]
  elif search.candidates[a].load.width != search.candidates[b].load.width:
    search.candidates[a].load.width < search.candidates[b].load.width
  else:
    search.candidates[a].load.offset < search.candidates[b].load.offset

proc prefixReducible(search: Search; depth, candidate: int): bool
    {.compileTime.} =
  ## Returns true when the byte union of the selected prefix plus candidate
  ## can be covered by at most `depth` widest loads. Replacing these
  ## `depth + 1` loads would contradict the already-proven minimum count.
  inc search.intervalGeneration
  let generation = search.intervalGeneration

  var selected = 0
  while selected < depth:
    let load = search.candidates[search.chosen[selected]].load
    var byteIndex = load.offset
    while byteIndex < load.offset + load.width:
      search.intervalMarks[byteIndex] = generation
      inc byteIndex
    inc selected
  let added = search.candidates[candidate].load
  var byteIndex = added.offset
  while byteIndex < added.offset + added.width:
    search.intervalMarks[byteIndex] = generation
    inc byteIndex

  # Greedy is optimal for covering ordered byte positions by fixed-width
  # intervals: cover the leftmost uncovered byte as far right as boundaries
  # permit.
  var replacementCount = 0
  var position = 0
  while position < search.byteLength:
    while position < search.byteLength and
        search.intervalMarks[position] != generation:
      inc position
    if position >= search.byteLength:
      break
    inc replacementCount
    if replacementCount > depth:
      return false
    let replacementOffset = min(position, search.byteLength - search.maxWidth)
    position = replacementOffset + search.maxWidth
  true

proc saveTailSolution(search: Search; depth, loadedBytes: int)
    {.compileTime.} =
  if not search.optimizeBytes:
    search.bestChosen.setLen(depth)
    var i = 0
    while i < depth:
      search.bestChosen[i] = search.chosen[i]
      inc i
    search.bestBytes = loadedBytes
    search.stop = true
  elif loadedBytes < search.bestBytes:
    search.bestBytes = loadedBytes
    search.bestChosen.setLen(depth)
    var i = 0
    while i < depth:
      search.bestChosen[i] = search.chosen[i]
      inc i

proc directTailOne(search: Search; depth, stateBase,
                   loadedBytes: int) {.compileTime.} =
  var candidate = 0
  while candidate < search.candidates.len and not search.stop:
    let width = search.candidates[candidate].load.width
    if search.optimizeBytes and loadedBytes + width >= search.bestBytes:
      break
    if not search.forbidden[candidate] and
        (not search.enforcePrefixIrreducible or
         not search.prefixReducible(depth, candidate)):
      let coverBase = candidate * search.words
      var coversAll = true
      var word = 0
      while word < search.words:
        if (search.states[stateBase + word] and
            not search.cover[coverBase + word]) != 0:
          coversAll = false
          break
        inc word
      if coversAll:
        search.chosen[depth] = candidate
        search.saveTailSolution(depth + 1, loadedBytes + width)
    inc candidate

proc directTailTwo(search: Search; depth, stateBase,
                   loadedBytes: int) {.compileTime.} =
  var branchPair = -1
  var orderIndex = 0
  if search.separatorOffsets.len != 0:
    # Static degree order is cheap and usually good. Sampling a few live rows
    # accounts for canonical exclusions and the current byte incumbent, which
    # can make their actual separator counts differ sharply near the leaves.
    var sampled = 0
    var bestCount = high(int)
    while orderIndex < search.pairOrder.len and sampled < 4:
      let pair = search.pairOrder[orderIndex]
      if bitIsSet(search.states, stateBase, pair):
        var eligible = 0
        var position = search.separatorOffsets[pair]
        let limit = search.separatorOffsets[pair + 1]
        while position < limit:
          let candidate = search.separatorItems[position]
          let width = search.candidates[candidate].load.width
          if search.optimizeBytes and
              loadedBytes + width + 1 >= search.bestBytes:
            break
          if not search.forbidden[candidate]:
            inc eligible
          inc position
        if eligible < bestCount:
          bestCount = eligible
          branchPair = pair
          if eligible == 0:
            break
        inc sampled
      inc orderIndex
  else:
    while orderIndex < search.pairOrder.len:
      let pair = search.pairOrder[orderIndex]
      if bitIsSet(search.states, stateBase, pair):
        branchPair = pair
        break
      inc orderIndex
  if branchPair < 0:
    return

  let branchBase = depth * search.candidates.len
  var branchCount = 0
  if search.separatorOffsets.len != 0:
    var position = search.separatorOffsets[branchPair]
    let limit = search.separatorOffsets[branchPair + 1]
    while position < limit:
      let candidate = search.separatorItems[position]
      if not search.forbidden[candidate]:
        search.branches[branchBase + branchCount] = candidate
        inc branchCount
      inc position
  else:
    var candidate = 0
    while candidate < search.candidates.len:
      if not search.forbidden[candidate] and
          bitIsSet(search.cover, candidate * search.words, branchPair):
        search.branches[branchBase + branchCount] = candidate
        inc branchCount
      inc candidate

  var branchIndex = 0
  while branchIndex < branchCount and not search.stop:
    let first = search.branches[branchBase + branchIndex]
    let firstWidth = search.candidates[first].load.width
    if (not search.optimizeBytes or
        loadedBytes + firstWidth + 1 < search.bestBytes) and
        (not search.enforcePrefixIrreducible or
         not search.prefixReducible(depth, first)):
      let firstCoverBase = first * search.words
      search.chosen[depth] = first
      let firstBytes = loadedBytes + firstWidth
      var tailPair = -1
      orderIndex = 0
      while orderIndex < search.pairOrder.len:
        let pair = search.pairOrder[orderIndex]
        if bitIsSet(search.states, stateBase, pair) and
            not bitIsSet(search.cover, firstCoverBase, pair):
          tailPair = pair
          break
        inc orderIndex
      if tailPair < 0:
        search.saveTailSolution(depth + 1, firstBytes)
      else:
        if search.separatorOffsets.len != 0:
          var position = search.separatorOffsets[tailPair]
          let limit = search.separatorOffsets[tailPair + 1]
          while position < limit and not search.stop:
            let second = search.separatorItems[position]
            let secondWidth = search.candidates[second].load.width
            if search.optimizeBytes and
                firstBytes + secondWidth >= search.bestBytes:
              break
            if not search.forbidden[second] and second != first:
              let secondCoverBase = second * search.words
              var coversAll = true
              var word = 0
              while word < search.words:
                if (search.states[stateBase + word] and
                    not (search.cover[firstCoverBase + word] or
                         search.cover[secondCoverBase + word])) != 0:
                  coversAll = false
                  break
                inc word
              if coversAll and
                  (not search.enforcePrefixIrreducible or
                   not search.prefixReducible(depth + 1, second)):
                search.chosen[depth + 1] = second
                search.saveTailSolution(
                  depth + 2, firstBytes + secondWidth)
            inc position
        else:
          var second = 0
          while second < search.candidates.len and not search.stop:
            let secondWidth = search.candidates[second].load.width
            if search.optimizeBytes and
                firstBytes + secondWidth >= search.bestBytes:
              break
            if not search.forbidden[second] and second != first and
                bitIsSet(search.cover, second * search.words, tailPair):
              let secondCoverBase = second * search.words
              var coversAll = true
              var word = 0
              while word < search.words:
                if (search.states[stateBase + word] and
                    not (search.cover[firstCoverBase + word] or
                         search.cover[secondCoverBase + word])) != 0:
                  coversAll = false
                  break
                inc word
              if coversAll and
                  (not search.enforcePrefixIrreducible or
                   not search.prefixReducible(depth + 1, second)):
                search.chosen[depth + 1] = second
                search.saveTailSolution(
                  depth + 2, firstBytes + secondWidth)
            inc second
    search.forbidden[first] = true
    inc branchIndex

  branchIndex = 0
  while branchIndex < branchCount:
    search.forbidden[search.branches[branchBase + branchIndex]] = false
    inc branchIndex

proc directTailThree(search: Search; depth, stateBase,
                     loadedBytes: int) {.compileTime.} =
  ## With three slots left, the normal full gain/lower-bound pass scans every
  ## candidate over every state word. A completion must contain a separator
  ## of one unresolved row, so canonically choose one of that row's separators
  ## in cheap-width candidate order, then use the exact two-slot oracle.
  var branchPair = -1
  var orderIndex = 0
  var sampled = 0
  var bestCount = high(int)
  while orderIndex < search.pairOrder.len and sampled < 4:
    let pair = search.pairOrder[orderIndex]
    if bitIsSet(search.states, stateBase, pair):
      var eligible = 0
      var position = search.separatorOffsets[pair]
      let limit = search.separatorOffsets[pair + 1]
      while position < limit:
        let candidate = search.separatorItems[position]
        let width = search.candidates[candidate].load.width
        if search.optimizeBytes and
            loadedBytes + width + 2 >= search.bestBytes:
          break
        if not search.forbidden[candidate]:
          inc eligible
        inc position
      if eligible < bestCount:
        bestCount = eligible
        branchPair = pair
        if eligible == 0:
          break
      inc sampled
    inc orderIndex
  if branchPair < 0:
    return

  let branchBase = depth * search.candidates.len
  var branchCount = 0
  var position = search.separatorOffsets[branchPair]
  let limit = search.separatorOffsets[branchPair + 1]
  while position < limit:
    let candidate = search.separatorItems[position]
    if not search.forbidden[candidate]:
      search.branches[branchBase + branchCount] = candidate
      inc branchCount
    inc position
  if branchCount == 0:
    return

  var branchIndex = 0
  while branchIndex < branchCount and not search.stop:
    let first = search.branches[branchBase + branchIndex]
    let firstWidth = search.candidates[first].load.width
    if loadedBytes + firstWidth + 2 < search.bestBytes and
        (not search.enforcePrefixIrreducible or
         not search.prefixReducible(depth, first)):
      let childBase = (depth + 1) * search.words
      let coverBase = first * search.words
      var childEmpty = true
      var word = 0
      while word < search.words:
        let childWord =
          search.states[stateBase + word] and
          not search.cover[coverBase + word]
        search.states[childBase + word] = childWord
        if childWord != 0:
          childEmpty = false
        inc word
      search.chosen[depth] = first
      if childEmpty:
        search.saveTailSolution(depth + 1, loadedBytes + firstWidth)
      else:
        search.directTailTwo(
          depth + 1, childBase, loadedBytes + firstWidth)
    search.forbidden[first] = true
    inc branchIndex

  branchIndex = 0
  while branchIndex < branchCount:
    search.forbidden[search.branches[branchBase + branchIndex]] = false
    inc branchIndex

proc directTailFour(search: Search; depth, stateBase,
                    loadedBytes: int) {.compileTime.} =
  ## The same exact canonical decomposition as the three-slot tail, with its
  ## child delegated to that oracle. It is reserved for targets up to five,
  ## where the call occurs only at the root or depth one. Larger targets keep
  ## the general bounds here: unconstrained depth-two branching can expand
  ## sharply on sparse K>=6 cases.
  var branchPair = -1
  var orderIndex = 0
  while orderIndex < search.pairOrder.len:
    let pair = search.pairOrder[orderIndex]
    if bitIsSet(search.states, stateBase, pair):
      branchPair = pair
      break
    inc orderIndex
  if branchPair < 0:
    return

  let branchBase = depth * search.candidates.len
  var branchCount = 0
  var position = search.separatorOffsets[branchPair]
  let limit = search.separatorOffsets[branchPair + 1]
  while position < limit:
    let candidate = search.separatorItems[position]
    if not search.forbidden[candidate]:
      search.branches[branchBase + branchCount] = candidate
      inc branchCount
    inc position
  if branchCount == 0:
    return

  var branchIndex = 0
  while branchIndex < branchCount and not search.stop:
    let first = search.branches[branchBase + branchIndex]
    let firstWidth = search.candidates[first].load.width
    if loadedBytes + firstWidth + 3 < search.bestBytes and
        (not search.enforcePrefixIrreducible or
         not search.prefixReducible(depth, first)):
      let childBase = (depth + 1) * search.words
      let coverBase = first * search.words
      var childEmpty = true
      var word = 0
      while word < search.words:
        let childWord =
          search.states[stateBase + word] and
          not search.cover[coverBase + word]
        search.states[childBase + word] = childWord
        if childWord != 0:
          childEmpty = false
        inc word
      search.chosen[depth] = first
      if childEmpty:
        search.saveTailSolution(depth + 1, loadedBytes + firstWidth)
      else:
        search.directTailThree(
          depth + 1, childBase, loadedBytes + firstWidth)
    search.forbidden[first] = true
    inc branchIndex

  branchIndex = 0
  while branchIndex < branchCount:
    search.forbidden[search.branches[branchBase + branchIndex]] = false
    inc branchIndex

proc exactSearch(search: Search; depth, stateBase, unresolved,
                 loadedBytes: int) {.compileTime.} =
  if search.stop:
    return
  if unresolved == 0:
    if not search.optimizeBytes:
      search.bestChosen.setLen(depth)
      var i = 0
      while i < depth:
        search.bestChosen[i] = search.chosen[i]
        inc i
      search.bestBytes = loadedBytes
      search.stop = true
    elif loadedBytes < search.bestBytes:
      search.bestBytes = loadedBytes
      search.bestChosen.setLen(depth)
      var i = 0
      while i < depth:
        search.bestChosen[i] = search.chosen[i]
        inc i
    return
  if depth >= search.target:
    return
  if search.optimizeBytes and loadedBytes >= search.bestBytes:
    return

  let budget = search.target - depth
  if budget == 1:
    search.directTailOne(depth, stateBase, loadedBytes)
    return
  if budget == 2:
    search.directTailTwo(depth, stateBase, loadedBytes)
    return
  if budget == 3 and search.separatorOffsets.len != 0 and
      (search.optimizeBytes or search.target <= 5):
    search.directTailThree(depth, stateBase, loadedBytes)
    return
  if budget == 4 and search.target <= 5 and search.optimizeBytes and
      search.words * 2 >= search.candidates.len and
      search.separatorOffsets.len != 0:
    search.directTailFour(depth, stateBase, loadedBytes)
    return

  let gainBase = depth * search.candidates.len
  search.fillGains(stateBase, gainBase)
  let lowerBound = search.countLowerBound(unresolved, budget, gainBase)
  if lowerBound > budget:
    return
  if search.optimizeBytes:
    # The target is already proven to be the globally minimum count. Any
    # completion therefore uses exactly the remaining target slots.
    let widthBound =
      search.gainWidthLowerBound(unresolved, budget, gainBase)
    if widthBound == high(int) or loadedBytes + widthBound >= search.bestBytes:
      return

  var branchPair = -1
  var orderIndex = 0
  while orderIndex < search.pairOrder.len:
    let pair = search.pairOrder[orderIndex]
    if bitIsSet(search.states, stateBase, pair):
      branchPair = pair
      break
    inc orderIndex
  if branchPair < 0:
    return

  let branchBase = depth * search.candidates.len
  var branchCount = 0
  if search.separatorOffsets.len != 0:
    var position = search.separatorOffsets[branchPair]
    let limit = search.separatorOffsets[branchPair + 1]
    while position < limit:
      let candidate = search.separatorItems[position]
      if not search.forbidden[candidate]:
        search.branches[branchBase + branchCount] = candidate
        inc branchCount
      inc position
  else:
    var candidate = 0
    while candidate < search.candidates.len:
      if not search.forbidden[candidate] and
          bitIsSet(search.cover, candidate * search.words, branchPair):
        search.branches[branchBase + branchCount] = candidate
        inc branchCount
      inc candidate
  if branchCount == 0:
    return

  # Insertion sort only separators of this pair, normally a small set.
  var i = 1
  while i < branchCount:
    let item = search.branches[branchBase + i]
    var j = i
    while j > 0 and
        search.betterBranch(
          item, search.branches[branchBase + j - 1], gainBase):
      search.branches[branchBase + j] =
        search.branches[branchBase + j - 1]
      dec j
    search.branches[branchBase + j] = item
    inc i

  # Branches partition solutions: branch i selects separator i and excludes
  # all earlier separators of this pair.
  i = 0
  while i < branchCount and not search.stop:
    let candidate = search.branches[branchBase + i]
    let gain = search.gains[gainBase + candidate]
    if gain > 0 and (not search.enforcePrefixIrreducible or
        not search.prefixReducible(depth, candidate)):
      let childBase = (depth + 1) * search.words
      let coverBase = candidate * search.words
      var word = 0
      while word < search.words:
        search.states[childBase + word] =
          search.states[stateBase + word] and
          not search.cover[coverBase + word]
        inc word
      search.chosen[depth] = candidate
      search.exactSearch(depth + 1, childBase, unresolved - gain,
                         loadedBytes +
                           search.candidates[candidate].load.width)
    search.forbidden[candidate] = true
    inc i

  i = 0
  while i < branchCount:
    search.forbidden[search.branches[branchBase + i]] = false
    inc i

proc separatorOrder(cover: seq[uint64]; candidateCount, words,
                    pairCount: int; counts: var seq[int]): seq[int]
    {.compileTime.} =
  result = newSeq[int](pairCount)
  counts = newSeq[int](pairCount)
  var histogram = newSeq[int](candidateCount + 1)
  var pair = 0
  while pair < pairCount:
    var candidate = 0
    while candidate < candidateCount:
      if bitIsSet(cover, candidate * words, pair):
        inc counts[pair]
      inc candidate
    inc histogram[counts[pair]]
    inc pair

  # Stable counting sort: separator degree lies in 0..candidateCount.
  # Pair indices arrive ascending, preserving the former deterministic tie.
  var positions = newSeq[int](candidateCount + 1)
  var running = 0
  var degree = 0
  while degree <= candidateCount:
    positions[degree] = running
    running += histogram[degree]
    inc degree
  pair = 0
  while pair < pairCount:
    degree = counts[pair]
    result[positions[degree]] = pair
    inc positions[degree]
    inc pair

proc separatorOrder(cover: seq[uint64]; candidateCount, words,
                    pairCount: int): seq[int] {.compileTime.} =
  var counts: seq[int]
  separatorOrder(cover, candidateCount, words, pairCount, counts)

proc buildSeparatorIndex(search: Search;
                         separatorCounts: seq[int]) {.compileTime.} =
  ## Pair-major candidate lists avoid rescanning every candidate in the
  ## heavily used direct two-slot tail. Candidate indices remain ascending,
  ## preserving canonical branch order and width-based early termination.
  doAssert separatorCounts.len == search.pairCount
  search.separatorOffsets = newSeq[int](search.pairCount + 1)
  var pair = 0
  while pair < search.pairCount:
    search.separatorOffsets[pair + 1] =
      search.separatorOffsets[pair] + separatorCounts[pair]
    inc pair

  search.separatorItems =
    newSeq[int](search.separatorOffsets[search.pairCount])
  pair = 0
  while pair < search.pairCount:
    var cursor = search.separatorOffsets[pair]
    var candidate = 0
    while candidate < search.candidates.len:
      if bitIsSet(search.cover, candidate * search.words, pair):
        search.separatorItems[cursor] = candidate
        inc cursor
      inc candidate
    inc pair

proc greedyCover(candidates: seq[Candidate]; cover: seq[uint64];
                 words, pairCount: int): seq[int] {.compileTime.} =
  if pairCount == 0:
    return @[]
  var unresolved = newSeq[uint64](words)
  var word = 0
  while word < words:
    unresolved[word] = not 0'u64
    inc word
  let tailBits = pairCount and 63
  if tailBits != 0:
    unresolved[words - 1] = (1'u64 shl tailBits) - 1
  var left = pairCount

  while left > 0:
    var best = -1
    var bestGain = 0
    var candidate = 0
    while candidate < candidates.len:
      var gain = 0
      word = 0
      while word < words:
        gain += countSetBits(
          unresolved[word] and cover[candidate * words + word])
        inc word
      if gain > bestGain or (gain == bestGain and gain > 0 and
          (candidates[candidate].load.width <
             candidates[best].load.width or
           (candidates[candidate].load.width ==
              candidates[best].load.width and
            candidates[candidate].load.offset <
              candidates[best].load.offset))):
        best = candidate
        bestGain = gain
      inc candidate
    if best < 0:
      raise newException(ValueError,
        "strings cannot be distinguished by valid byte loads")
    result.add best
    word = 0
    while word < words:
      unresolved[word] = unresolved[word] and
        not cover[best * words + word]
      inc word
    left -= bestGain

  # Remove any candidate made redundant by later greedy choices.
  var i = result.len - 1
  while i >= 0:
    var allCovered = true
    var pair = 0
    while pair < pairCount:
      var coveredPair = false
      var j = 0
      while j < result.len:
        if j != i and bitIsSet(cover, result[j] * words, pair):
          coveredPair = true
          break
        inc j
      if not coveredPair:
        allCovered = false
        break
      inc pair
    if allCovered:
      result.delete(i)
    dec i

proc rootGainLowerBound(cover: seq[uint64]; candidateCount, words,
                        pairCount, budget: int): int {.compileTime.} =
  var gains = newSeq[int](candidateCount)
  var candidate = 0
  while candidate < candidateCount:
    var word = 0
    while word < words:
      gains[candidate] += countSetBits(cover[candidate * words + word])
      inc word
    inc candidate
  var used = newSeq[bool](candidateCount)
  var sum = 0
  while result < budget and sum < pairCount:
    var best = -1
    var bestGain = 0
    candidate = 0
    while candidate < candidateCount:
      if not used[candidate] and gains[candidate] > bestGain:
        best = candidate
        bestGain = gains[candidate]
      inc candidate
    if best < 0:
      return budget + 1
    used[best] = true
    sum += bestGain
    inc result
  if sum < pairCount:
    budget + 1
  else:
    result

proc directSmallCover(candidates: seq[Candidate]; cover: seq[uint64];
                      words, pairCount, target: int;
                      optimizeBytes: bool;
                      chosen: var seq[int]): bool {.compileTime.} =
  if target < 1 or target > 3:
    return false
  let tailBits = pairCount and 63
  let tailMask =
    if tailBits == 0: not 0'u64
    else: (1'u64 shl tailBits) - 1
  var bestBytes = high(int)
  if optimizeBytes:
    var maximumWidth = 0
    var candidate = 0
    while candidate < candidates.len:
      maximumWidth = max(maximumWidth, candidates[candidate].load.width)
      inc candidate
    bestBytes = target * maximumWidth + 1

  var first = 0
  while first < candidates.len:
    if target == 1:
      var coversAll = true
      var word = 0
      while word < words:
        let required = if word == words - 1: tailMask else: not 0'u64
        if (cover[first * words + word] and required) != required:
          coversAll = false
          break
        inc word
      if coversAll:
        let bytes = candidates[first].load.width
        if not optimizeBytes:
          chosen = @[first]
          return true
        if bytes < bestBytes:
          bestBytes = bytes
          chosen = @[first]
    elif target == 2:
      var second = first + 1
      while second < candidates.len:
        let bytes = candidates[first].load.width +
                    candidates[second].load.width
        if optimizeBytes and bytes >= bestBytes:
          break
        if not optimizeBytes or bytes < bestBytes:
          var coversAll = true
          var word = 0
          while word < words:
            let required =
              if word == words - 1: tailMask else: not 0'u64
            if ((cover[first * words + word] or
                 cover[second * words + word]) and required) != required:
              coversAll = false
              break
            inc word
          if coversAll:
            if not optimizeBytes:
              chosen = @[first, second]
              return true
            bestBytes = bytes
            chosen = @[first, second]
        inc second
    else:
      var second = first + 1
      while second < candidates.len:
        let pairBytes = candidates[first].load.width +
                        candidates[second].load.width
        var third = second + 1
        while third < candidates.len:
          let bytes = pairBytes + candidates[third].load.width
          if optimizeBytes and bytes >= bestBytes:
            break
          if not optimizeBytes or bytes < bestBytes:
            var coversAll = true
            var word = 0
            while word < words:
              let required =
                if word == words - 1: tailMask else: not 0'u64
              if ((cover[first * words + word] or
                   cover[second * words + word] or
                   cover[third * words + word]) and required) != required:
                coversAll = false
                break
              inc word
            if coversAll:
              if not optimizeBytes:
                chosen = @[first, second, third]
                return true
              bestBytes = bytes
              chosen = @[first, second, third]
          inc third
        inc second
    inc first
  chosen.len == target

proc directThreeTiered(candidates: seq[Candidate]; cover: seq[uint64];
                       words, pairCount: int;
                       chosen: var seq[int]): bool {.compileTime.} =
  ## Exact fixed-K=3 byte optimization. Width classes and total byte cost are
  ## enumerated in ascending order. For fixed first/second loads, any third
  ## load must separate every still-unresolved row, hence must belong to the
  ## separator list of a minimum-degree unresolved row.
  var classStart: array[4, int]
  var classEnd: array[4, int]
  var widthClass = 0
  while widthClass < 4:
    classStart[widthClass] = candidates.len
    classEnd[widthClass] = candidates.len
    inc widthClass
  var candidate = 0
  while candidate < candidates.len:
    let class =
      case candidates[candidate].load.width
      of 1: 0
      of 2: 1
      of 4: 2
      else: 3
    if classStart[class] == candidates.len:
      classStart[class] = candidate
    classEnd[class] = candidate + 1
    inc candidate

  var separatorCounts = newSeq[int](pairCount * 4)
  var pair = 0
  while pair < pairCount:
    widthClass = 0
    while widthClass < 4:
      candidate = classStart[widthClass]
      while candidate < classEnd[widthClass]:
        if bitIsSet(cover, candidate * words, pair):
          inc separatorCounts[pair * 4 + widthClass]
        inc candidate
      inc widthClass
    inc pair

  var separatorOffsets = newSeq[int](pairCount * 4 + 1)
  var cell = 0
  while cell < pairCount * 4:
    separatorOffsets[cell + 1] =
      separatorOffsets[cell] + separatorCounts[cell]
    inc cell
  var separatorItems = newSeq[int](separatorOffsets[pairCount * 4])
  var separatorCursor = newSeq[int](pairCount * 4)
  cell = 0
  while cell < pairCount * 4:
    separatorCursor[cell] = separatorOffsets[cell]
    inc cell
  pair = 0
  while pair < pairCount:
    widthClass = 0
    while widthClass < 4:
      cell = pair * 4 + widthClass
      candidate = classStart[widthClass]
      while candidate < classEnd[widthClass]:
        if bitIsSet(cover, candidate * words, pair):
          separatorItems[separatorCursor[cell]] = candidate
          inc separatorCursor[cell]
        inc candidate
      inc widthClass
    inc pair

  # Pair order depends on the required third width.
  var classPairOrder = newSeq[int](pairCount * 4)
  widthClass = 0
  while widthClass < 4:
    let maximumDegree =
      classEnd[widthClass] - classStart[widthClass]
    var histogram = newSeq[int](maximumDegree + 1)
    pair = 0
    while pair < pairCount:
      inc histogram[separatorCounts[pair * 4 + widthClass]]
      inc pair
    var positions = newSeq[int](maximumDegree + 1)
    var running = 0
    var degree = 0
    while degree <= maximumDegree:
      positions[degree] = running
      running += histogram[degree]
      inc degree
    pair = 0
    while pair < pairCount:
      degree = separatorCounts[pair * 4 + widthClass]
      classPairOrder[widthClass * pairCount + positions[degree]] = pair
      inc positions[degree]
      inc pair
    inc widthClass

  let tailBits = pairCount and 63
  let tailMask =
    if tailBits == 0: not 0'u64
    else: (1'u64 shl tailBits) - 1
  var totalBytes = 3
  while totalBytes <= 24:
    var firstClass = 0
    while firstClass < 4:
      var secondClass = firstClass
      while secondClass < 4:
        var thirdClass = secondClass
        while thirdClass < 4:
          if AllowedWidths[firstClass] + AllowedWidths[secondClass] +
              AllowedWidths[thirdClass] == totalBytes and
              classStart[firstClass] < classEnd[firstClass] and
              classStart[secondClass] < classEnd[secondClass] and
              classStart[thirdClass] < classEnd[thirdClass]:
            var first = classStart[firstClass]
            while first < classEnd[firstClass]:
              var second = classStart[secondClass]
              if firstClass == secondClass:
                second = first + 1
              while second < classEnd[secondClass]:
                var branchPair = -1
                var orderIndex = 0
                while orderIndex < pairCount:
                  let orderedPair =
                    classPairOrder[thirdClass * pairCount + orderIndex]
                  if not bitIsSet(cover, first * words, orderedPair) and
                      not bitIsSet(cover, second * words, orderedPair):
                    branchPair = orderedPair
                    break
                  inc orderIndex

                if branchPair >= 0:
                  let thirdCell = branchPair * 4 + thirdClass
                  var thirdPosition = separatorOffsets[thirdCell]
                  let thirdLimit = separatorOffsets[thirdCell + 1]
                  if thirdClass == secondClass:
                    while thirdPosition < thirdLimit and
                        separatorItems[thirdPosition] <= second:
                      inc thirdPosition
                  while thirdPosition < thirdLimit:
                    let third = separatorItems[thirdPosition]
                    var coversAll = true
                    var word = 0
                    while word < words:
                      let required =
                        if word == words - 1: tailMask else: not 0'u64
                      if ((cover[first * words + word] or
                           cover[second * words + word] or
                           cover[third * words + word]) and required) !=
                          required:
                        coversAll = false
                        break
                      inc word
                    if coversAll:
                      chosen = @[first, second, third]
                      return true
                    inc thirdPosition
                inc second
              inc first
          inc thirdClass
        inc secondClass
      inc firstClass
    inc totalBytes
  false

proc newSearch(candidates: seq[Candidate]; cover: seq[uint64];
               words, pairCount, target: int;
               pairOrder: seq[int]): Search {.compileTime.} =
  new(result)
  result.candidates = candidates
  result.cover = cover
  result.pairOrder = pairOrder
  result.words = words
  result.pairCount = pairCount
  result.target = target
  result.bestBytes = high(int)
  result.gains = newSeq[int]((target + 1) * candidates.len)
  result.topMarks = newSeq[int](candidates.len)
  result.widthTopGains = newSeq[int](4 * max(target, 1))
  result.forbidden = newSeq[bool](candidates.len)
  result.states = newSeq[uint64]((target + 1) * words)
  result.branches = newSeq[int]((target + 1) * candidates.len)
  result.chosen = newSeq[int](target)
  var word = 0
  while word < words:
    result.states[word] = not 0'u64
    inc word
  let tailBits = pairCount and 63
  if tailBits != 0:
    result.states[words - 1] = (1'u64 shl tailBits) - 1

proc buildCandidates(byteLength, words, onlyWidth: int;
                     byteCover: seq[uint64];
                     candidates: var seq[Candidate];
                     cover: var seq[uint64]) {.compileTime.} =
  var candidateCount = 0
  var widthIndex = 0
  while widthIndex < AllowedWidths.len:
    let width = AllowedWidths[widthIndex]
    if width <= byteLength and (onlyWidth == 0 or width == onlyWidth):
      candidateCount += byteLength - width + 1
    inc widthIndex

  candidates = newSeq[Candidate](candidateCount)
  cover = newSeq[uint64](candidateCount * words)
  var candidate = 0
  widthIndex = 0
  while widthIndex < AllowedWidths.len:
    let width = AllowedWidths[widthIndex]
    if width <= byteLength and (onlyWidth == 0 or width == onlyWidth):
      var offset = 0
      while offset <= byteLength - width:
        candidates[candidate].load = ByteLoad(offset: offset, width: width)
        var byteIndex = offset
        while byteIndex < offset + width:
          var word = 0
          while word < words:
            cover[candidate * words + word] =
              cover[candidate * words + word] or
              byteCover[byteIndex * words + word]
            inc word
          inc byteIndex
        inc candidate
        inc offset
    inc widthIndex

proc widestAllowed(byteLength: int): int {.compileTime.} =
  var widthIndex = 0
  while widthIndex < AllowedWidths.len:
    if AllowedWidths[widthIndex] <= byteLength:
      result = AllowedWidths[widthIndex]
    inc widthIndex

proc buildBytePairCover(strings: openArray[string]; byteLength: int;
                        pairCount: var int; words: var int;
                        byteCover: var seq[uint64]) {.compileTime.} =
  let originalPairCount = strings.len * (strings.len - 1) div 2

  # With width-1 loads present, Sep(D1) is a subset of Sep(D2) exactly when
  # differing-byte set D1 is a subset of D2. Keep only inclusion-minimal
  # difference sets. Deduplicate incrementally, but abandon this optional
  # kernel if difference-set diversity exceeds its bounded work budget.
  let differenceWords = (byteLength + 63) shr 6
  if originalPairCount >= 64 and
      (originalPairCount > 512 or
       originalPairCount * originalPairCount * differenceWords <= 2_000_000):
    const MaxMinimalDifferences = 512
    let byteWords = differenceWords
    var minimal = newSeq[uint64](MaxMinimalDifferences * byteWords)
    var scratch = newSeq[uint64](byteWords)
    var singletonBytes = newSeq[bool](byteLength)
    var singletonCount = 0
    var projectionTableSize = 1
    while projectionTableSize < strings.len * 2:
      projectionTableSize = projectionTableSize shl 1
    var projectionSlots = newSeq[int](projectionTableSize)
    var projectionStamps = newSeq[int](projectionTableSize)
    var projectionHashes = newSeq[uint64](strings.len)
    var projectionGeneration = 0
    var allPairsImplied = false
    var minimalCount = 0
    var tooMany = false
    var left = 0
    while left < strings.len and not tooMany and not allPairsImplied and
        singletonCount < byteLength:
      let singletonsAtOuterStart = singletonCount
      var right = left + 1
      while right < strings.len and not tooMany:
        var word = 0
        while word < byteWords:
          scratch[word] = 0
          inc word
        var byteIndex = 0
        var redundantBySingleton = false
        while byteIndex < byteLength:
          if strings[left][byteIndex] != strings[right][byteIndex]:
            if singletonBytes[byteIndex]:
              redundantBySingleton = true
              break
            scratch[byteIndex shr 6] =
              scratch[byteIndex shr 6] or
              (1'u64 shl (byteIndex and 63))
          inc byteIndex

        # If retained E is a subset of new D, D is implied and discarded.
        var redundant = redundantBySingleton
        var item = 0
        while item < minimalCount and not redundant:
          var subset = true
          word = 0
          while word < byteWords:
            if (minimal[item * byteWords + word] and not scratch[word]) != 0:
              subset = false
              break
            inc word
          if subset:
            redundant = true
            break

          inc item
        if not redundant:
          # New D may itself imply retained supersets. Compact survivors.
          var destination = 0
          item = 0
          while item < minimalCount:
            var newIsSubset = true
            word = 0
            while word < byteWords:
              if (scratch[word] and
                  not minimal[item * byteWords + word]) != 0:
                newIsSubset = false
                break
              inc word
            if not newIsSubset:
              if destination != item:
                word = 0
                while word < byteWords:
                  minimal[destination * byteWords + word] =
                    minimal[item * byteWords + word]
                  inc word
              inc destination
            inc item
          minimalCount = destination

          if minimalCount >= MaxMinimalDifferences:
            tooMany = true
          else:
            word = 0
            while word < byteWords:
              minimal[minimalCount * byteWords + word] = scratch[word]
              inc word
            var bitCount = 0
            var singletonByte = -1
            word = 0
            while word < byteWords:
              let bits = scratch[word]
              bitCount += countSetBits(bits)
              if bits != 0:
                singletonByte =
                  (word shl 6) + countTrailingZeroBits(bits)
              inc word
            if bitCount == 1:
              singletonBytes[singletonByte] = true
              inc singletonCount
            inc minimalCount
        inc right
      inc left

      # If retained singleton bytes already give every string a unique
      # projection, they imply every remaining pair constraint. Hashes only
      # choose probe slots; equal hashes receive exact projection comparison.
      if singletonCount > singletonsAtOuterStart and
          singletonCount < byteLength and not tooMany:
        inc projectionGeneration
        var projectionsUnique = true
        var stringIndex = 0
        while stringIndex < strings.len and projectionsUnique:
          var projectionHash = 1469598103934665603'u64
          var byteIndex = 0
          while byteIndex < byteLength:
            if singletonBytes[byteIndex]:
              projectionHash =
                (projectionHash xor uint64(ord(strings[stringIndex][byteIndex]))) *
                1099511628211'u64
            inc byteIndex
          projectionHash = avalancheHash(projectionHash)
          projectionHashes[stringIndex] = projectionHash
          var slot = int(projectionHash and uint64(projectionTableSize - 1))
          while projectionStamps[slot] == projectionGeneration:
            let prior = projectionSlots[slot]
            if projectionHashes[prior] == projectionHash:
              var equal = true
              byteIndex = 0
              while byteIndex < byteLength:
                if singletonBytes[byteIndex] and
                    strings[prior][byteIndex] != strings[stringIndex][byteIndex]:
                  equal = false
                  break
                inc byteIndex
              if equal:
                projectionsUnique = false
                break
            slot = (slot + 1) and (projectionTableSize - 1)
          if projectionsUnique:
            projectionStamps[slot] = projectionGeneration
            projectionSlots[slot] = stringIndex
          inc stringIndex
        allPairsImplied = projectionsUnique

    if not tooMany:
      pairCount = minimalCount
      words = (pairCount + 63) shr 6
      byteCover = newSeq[uint64](byteLength * words)

      var item = 0
      while item < minimalCount:
        var byteIndex = 0
        while byteIndex < byteLength:
          if (minimal[item * byteWords + (byteIndex shr 6)] and
              (1'u64 shl (byteIndex and 63))) != 0:
            byteCover[byteIndex * words + (item shr 6)] =
              byteCover[byteIndex * words + (item shr 6)] or
              (1'u64 shl (item and 63))
          inc byteIndex
        inc item
      return

  pairCount = originalPairCount
  words = (pairCount + 63) shr 6
  byteCover = newSeq[uint64](byteLength * words)
  var pair = 0
  var left = 0
  while left < strings.len:
    var right = left + 1
    while right < strings.len:
      var byteIndex = 0
      while byteIndex < byteLength:
        if strings[left][byteIndex] != strings[right][byteIndex]:
          byteCover[byteIndex * words + (pair shr 6)] =
            byteCover[byteIndex * words + (pair shr 6)] or
            (1'u64 shl (pair and 63))
        inc byteIndex
      inc pair
      inc right
    inc left

type
  LargeScore = object
    gain: int
    width: int

proc largeNextPowerOfTwo(value: int): int {.compileTime.} =
  result = 1
  while result < value:
    result = result shl 1

proc largeScoreLoad(strings: openArray[string]; loads: seq[ByteLoad];
                    candidate: int; classOf, sample: seq[int]; oldPairs: int;
                    stamps, keyClasses: var seq[int]; keys,
                    counts: var seq[uint64]; generation: var int): int
    {.compileTime.} =
  inc generation
  let generationHere = generation
  let load = loads[candidate]
  var newPairs = 0
  var sampleIndex = 0
  while sampleIndex < sample.len:
    let stringIndex = sample[sampleIndex]
    let classId = classOf[stringIndex]
    let value = loadValue(strings[stringIndex], load.offset, load.width)
    let hash = avalancheHash(
      value xor (uint64(classId) * 0x9E3779B97F4A7C15'u64))
    var slot = int(hash and uint64(stamps.len - 1))
    while stamps[slot] == generationHere and
        (keyClasses[slot] != classId or keys[slot] != value):
      slot = (slot + 1) and (stamps.len - 1)
    if stamps[slot] != generationHere:
      stamps[slot] = generationHere
      keyClasses[slot] = classId
      keys[slot] = value
      counts[slot] = 1
    else:
      newPairs += int(counts[slot])
      inc counts[slot]
    inc sampleIndex
  oldPairs - newPairs

proc largeRefine(strings: openArray[string]; loads: seq[ByteLoad];
                 candidate: int; classOf: var seq[int];
                 classSizes: var seq[int]; classCount: var int;
                 stamps, keyClasses: var seq[int]; keys,
                 counts: var seq[uint64]; generation: var int) {.compileTime.} =
  inc generation
  let generationHere = generation
  var nextClass = newSeq[int](classOf.len)
  var newSizes: seq[int] = @[]
  let load = loads[candidate]
  var stringIndex = 0
  while stringIndex < classOf.len:
    let oldClass = classOf[stringIndex]
    let value = loadValue(strings[stringIndex], load.offset, load.width)
    let hash = avalancheHash(
      value xor (uint64(oldClass) * 0x9E3779B97F4A7C15'u64))
    var slot = int(hash and uint64(stamps.len - 1))
    while stamps[slot] == generationHere and
        (keyClasses[slot] != oldClass or keys[slot] != value):
      slot = (slot + 1) and (stamps.len - 1)
    if stamps[slot] != generationHere:
      stamps[slot] = generationHere
      keyClasses[slot] = oldClass
      keys[slot] = value
      let newClass = newSizes.len
      counts[slot] = uint64(newClass)
      newSizes.add 1
      nextClass[stringIndex] = newClass
    else:
      let newClass = int(counts[slot])
      inc newSizes[newClass]
      nextClass[stringIndex] = newClass
    inc stringIndex
  classOf = nextClass
  classSizes = newSizes
  classCount = newSizes.len

proc largeSample(classOf: seq[int]; classCount, limit, round: int): seq[int]
    {.compileTime.} =
  let stringCount = classOf.len
  if stringCount == 0:
    return
  var first = newSeq[int](classCount)
  var second = newSeq[int](classCount)
  var classId = 0
  while classId < classCount:
    first[classId] = -1
    second[classId] = -1
    inc classId
  var stringIndex = 0
  while stringIndex < stringCount:
    let currentClass = classOf[stringIndex]
    if first[currentClass] < 0:
      first[currentClass] = stringIndex
    elif second[currentClass] < 0:
      second[currentClass] = stringIndex
    inc stringIndex

  var seen = newSeq[bool](stringCount)
  var pass = 0
  while pass < 2 and result.len < limit:
    classId = (round + pass) mod max(classCount, 1)
    var visited = 0
    while visited < classCount and result.len < limit:
      let item = if pass == 0: first[classId] else: second[classId]
      if item >= 0 and not seen[item]:
        seen[item] = true
        result.add item
      classId = (classId + 1) mod max(classCount, 1)
      inc visited
    inc pass
  let remaining = limit - result.len
  var sampleIndex = 0
  while sampleIndex < remaining:
    let item = ((sampleIndex + round * 17) * stringCount div
                max(remaining, 1)) mod stringCount
    if not seen[item]:
      seen[item] = true
      result.add item
    inc sampleIndex
  stringIndex = 0
  while stringIndex < stringCount and result.len < limit:
    if not seen[stringIndex]:
      seen[stringIndex] = true
      result.add stringIndex
    inc stringIndex

proc largeCollisionPairs(classOf: seq[int]; sample: seq[int];
                          pairA, pairB: var seq[int]) {.compileTime.} =
  var sampleIndex = 0
  while sampleIndex < sample.len:
    var prior = sampleIndex - 1
    var added = 0
    while prior >= 0 and added < 4:
      if classOf[sample[prior]] == classOf[sample[sampleIndex]]:
        pairA.add prior
        pairB.add sampleIndex
        inc added
      dec prior
    inc sampleIndex

proc largeOneHotCover(strings: openArray[string];
                      answer: var seq[ByteLoad]): bool {.compileTime.} =
  let byteLength = strings[0].len
  if byteLength < 8 or strings.len != byteLength + 1:
    return false
  var seen = newSeq[bool](byteLength)
  var stringIndex = 1
  while stringIndex < strings.len:
    var differingByte = -1
    var differenceCount = 0
    var byteIndex = 0
    while byteIndex < byteLength:
      if strings[0][byteIndex] != strings[stringIndex][byteIndex]:
        differingByte = byteIndex
        inc differenceCount
        if differenceCount > 1:
          return false
      inc byteIndex
    if differenceCount != 1:
      return false
    seen[differingByte] = true
    inc stringIndex
  for item in seen:
    if not item:
      return false
  let blockCount = (byteLength + 7) div 8
  var blockIndex = 0
  while blockIndex < blockCount:
    answer.add ByteLoad(offset: min(blockIndex * 8, byteLength - 8), width: 8)
    inc blockIndex
  true

proc largeTrySingle(strings: openArray[string];
                    found: var ByteLoad): bool {.compileTime.} =
  let byteLength = strings[0].len
  let tableSize = largeNextPowerOfTwo(max(8, strings.len * 2))
  var stamps = newSeq[int](tableSize)
  var keys = newSeq[uint64](tableSize)
  var generation = 0
  for width in AllowedWidths:
    if width <= byteLength:
      let offsetStep = max(1, byteLength div 64)
      var offset = 0
      while offset <= byteLength - width:
        if offset == 0 or offset == byteLength - width or
            offset mod offsetStep == 0:
          inc generation
          var unique = true
          var stringIndex = 0
          while stringIndex < strings.len:
            let value = loadValue(strings[stringIndex], offset, width)
            var slot = int(avalancheHash(value) and uint64(tableSize - 1))
            while stamps[slot] == generation and keys[slot] != value:
              slot = (slot + 1) and (tableSize - 1)
            if stamps[slot] == generation:
              unique = false
              break
            stamps[slot] = generation
            keys[slot] = value
            inc stringIndex
          if unique:
            found = ByteLoad(offset: offset, width: width)
            return true
        inc offset
  false

proc largeChoose(strings: openArray[string]): seq[ByteLoad]
    {.compileTime.} =
  if strings.len <= 1:
    return @[]
  let byteLength = strings[0].len
  if largeOneHotCover(strings, result):
    return result
  var single: ByteLoad
  if largeTrySingle(strings, single):
    return @[single]
  var loads: seq[ByteLoad] = @[]
  for width in AllowedWidths:
    if width <= byteLength:
      var offset = 0
      while offset <= byteLength - width:
        loads.add ByteLoad(offset: offset, width: width)
        inc offset
  if loads.len == 0:
    raise newException(ValueError, "strings cannot be distinguished")

  let tableSize = largeNextPowerOfTwo(max(8, strings.len * 4))
  var stamps = newSeq[int](tableSize)
  var keyClasses = newSeq[int](tableSize)
  var keys = newSeq[uint64](tableSize)
  var counts = newSeq[uint64](tableSize)
  var generation = 1
  var classOf = newSeq[int](strings.len)
  var classSizes = @[strings.len]
  var classCount = 1
  var used = newSeq[bool](loads.len)
  var selected: seq[ByteLoad] = @[]
  const PerWidthTop = 256
  let topLimit = if loads.len <= 512: PerWidthTop else: 12
  var topCandidates = newSeq[int](AllowedWidths.len * PerWidthTop)
  var topScores = newSeq[LargeScore](AllowedWidths.len * PerWidthTop)
  var topLengths = newSeq[int](AllowedWidths.len)
  var profilePool = newSeq[bool](loads.len)
  let sampleLimit = min(strings.len, 256)
  let wideStep = max(1, byteLength div 512)
  let narrowStep = max(1, byteLength div 64)
  var round = 0
  while classCount < strings.len and selected.len < 64:
    var widthClass = 0
    while widthClass < AllowedWidths.len:
      topLengths[widthClass] = 0
      inc widthClass
    let sample = largeSample(classOf, classCount, sampleLimit, round)
    var pairA: seq[int] = @[]
    var pairB: seq[int] = @[]
    largeCollisionPairs(classOf, sample, pairA, pairB)
    var sampleValues = newSeq[uint64](sample.len)
    var candidate = 0
    while candidate < loads.len:
      let load = loads[candidate]
      let inPool = round == 0 or profilePool[candidate] or
        (load.width == 8 and load.offset mod wideStep == 0) or
        (load.width < 8 and load.offset mod narrowStep == 0)
      if not used[candidate] and inPool:
        var sampleIndex = 0
        while sampleIndex < sample.len:
          sampleValues[sampleIndex] = loadValue(
            strings[sample[sampleIndex]], load.offset, load.width)
          inc sampleIndex
        var screenGain = 0
        var pairIndex = 0
        while pairIndex < pairA.len:
          if sampleValues[pairA[pairIndex]] != sampleValues[pairB[pairIndex]]:
            inc screenGain
          inc pairIndex
        widthClass = case load.width
          of 1: 0
          of 2: 1
          of 4: 2
          else: 3
        let base = widthClass * PerWidthTop
        var length = topLengths[widthClass]
        var insert = length
        let score = LargeScore(gain: screenGain, width: load.width)
        while insert > 0 and
            (score.gain > topScores[base + insert - 1].gain or
             (score.gain == topScores[base + insert - 1].gain and
              score.width < topScores[base + insert - 1].width)):
          if insert < topLimit:
            topCandidates[base + insert] = topCandidates[base + insert - 1]
            topScores[base + insert] = topScores[base + insert - 1]
          dec insert
        if insert < topLimit:
          topCandidates[base + insert] = candidate
          topScores[base + insert] = score
          if length < topLimit:
            inc length
          topLengths[widthClass] = length
      inc candidate

    if round == 0:
      widthClass = 0
      while widthClass < AllowedWidths.len:
        let base = widthClass * PerWidthTop
        var topIndex = 0
        while topIndex < topLengths[widthClass]:
          profilePool[topCandidates[base + topIndex]] = true
          inc topIndex
        inc widthClass

    var fullSample = newSeq[int](strings.len)
    var stringIndex = 0
    while stringIndex < strings.len:
      fullSample[stringIndex] = stringIndex
      inc stringIndex
    var oldPairs = 0
    for size in classSizes:
      oldPairs += size * (size - 1) div 2
    var bestCandidate = -1
    var bestGain = -1
    var bestWidth = high(int)
    widthClass = 0
    while widthClass < AllowedWidths.len:
      let base = widthClass * PerWidthTop
      var topIndex = 0
      while topIndex < topLengths[widthClass]:
        candidate = topCandidates[base + topIndex]
        let gain = largeScoreLoad(strings, loads, candidate, classOf,
          fullSample, oldPairs, stamps, keyClasses, keys, counts, generation)
        let width = loads[candidate].width
        if gain > bestGain or (gain == bestGain and width < bestWidth):
          bestCandidate = candidate
          bestGain = gain
          bestWidth = width
        inc topIndex
      inc widthClass
    if bestCandidate < 0 or bestGain <= 0:
      break
    used[bestCandidate] = true
    selected.add loads[bestCandidate]
    largeRefine(strings, loads, bestCandidate, classOf, classSizes, classCount,
      stamps, keyClasses, keys, counts, generation)
    inc round

  # Exact repair: find one unresolved collision, then load widest interval
  # covering its first differing byte. No pair matrix or O(N²) signature scan.
  let maxWidth = widestAllowed(byteLength)
  while classCount < strings.len:
    var left = -1
    var right = -1
    var stringIndex = 0
    while stringIndex < strings.len and left < 0:
      let currentClass = classOf[stringIndex]
      if classSizes[currentClass] > 1:
        left = stringIndex
        var other = stringIndex + 1
        while other < strings.len:
          if classOf[other] == currentClass:
            right = other
            break
          inc other
      inc stringIndex
    if left < 0 or right < 0:
      break
    var differingByte = 0
    while differingByte < byteLength and
        strings[left][differingByte] == strings[right][differingByte]:
      inc differingByte
    if differingByte >= byteLength:
      raise newException(ValueError, "duplicate strings in large heuristic")
    let repairOffset = min(differingByte, byteLength - maxWidth)
    var repairCandidate = -1
    var candidate = 0
    while candidate < loads.len:
      if loads[candidate].offset == repairOffset and
          loads[candidate].width == maxWidth:
        repairCandidate = candidate
        break
      inc candidate
    if repairCandidate < 0 or used[repairCandidate]:
      # The widest interval cannot already be used if it failed to separate
      # this pair; retain a safe fallback scan for narrow boundary cases.
      candidate = 0
      while candidate < loads.len:
        if not used[candidate] and
            loadValue(strings[left], loads[candidate].offset,
                      loads[candidate].width) !=
              loadValue(strings[right], loads[candidate].offset,
                        loads[candidate].width):
          repairCandidate = candidate
          break
        inc candidate
    if repairCandidate < 0:
      raise newException(ValueError, "large heuristic found no separator")
    used[repairCandidate] = true
    selected.add loads[repairCandidate]
    largeRefine(strings, loads, repairCandidate, classOf, classSizes,
      classCount, stamps, keyClasses, keys, counts, generation)

  if not uniqueLoadSignatures(strings, selected):
    raise newException(ValueError, "large heuristic failed to distinguish strings")
  var sortIndex = 1
  while sortIndex < selected.len:
    let item = selected[sortIndex]
    var position = sortIndex
    while position > 0 and item < selected[position - 1]:
      selected[position] = selected[position - 1]
      dec position
    selected[position] = item
    inc sortIndex
  selected

proc chooseByteLoads*(strings: openArray[string]): seq[ByteLoad]
    {.compileTime.} =
  let byteLength = validateInput(strings)
  if strings.len <= 1:
    return @[]
  let originalPairCount = strings.len * (strings.len - 1) div 2
  let pairWords = (originalPairCount + 63) shr 6
  let estimatedByteCoverBytes = int64(byteLength) * int64(pairWords) * 8'i64
  var rawCandidateCount = 0
  for width in AllowedWidths:
    if width <= byteLength:
      rawCandidateCount += byteLength - width + 1
  let estimatedCandidateCoverBytes =
    int64(rawCandidateCount) * int64(pairWords) * 8'i64
  const LargeKernelByteLimit = 64'i64 * 1024'i64 * 1024'i64
  if estimatedByteCoverBytes + estimatedCandidateCoverBytes >
      LargeKernelByteLimit:
    return largeChoose(strings)
  var singleLoad: ByteLoad
  if findSingleLoad(strings, byteLength, singleLoad):
    return @[singleLoad]

  # A block differs iff at least one contained byte differs. Building load
  # coverage by OR-ing byte-pair bitsets avoids C*N uint64 load values and
  # their repeated comparisons in Nim VM.
  var kernelPairCount = originalPairCount
  var kernelWords = (kernelPairCount + 63) shr 6
  var byteCover: seq[uint64]
  buildBytePairCover(
    strings, byteLength, kernelPairCount, kernelWords, byteCover)

  # Primary theorem: every narrower load is contained in some widest valid
  # load. Replacing it preserves all distinctions at the same group count.
  # Therefore minimum count can be proven using widest loads only.
  let maxWidth = widestAllowed(byteLength)
  var countCandidates: seq[Candidate]
  var countCover: seq[uint64]
  buildCandidates(byteLength, kernelWords, maxWidth,
                  byteCover, countCandidates, countCover)
  var countWords = kernelWords
  var countPairs = kernelPairCount
  countCandidates.compressCandidates(countCover, countWords)
  var reductionRounds = 0
  while reductionRounds < 8 and reducePairConstraints(
      countCandidates, countCover, countPairs, countWords):
    countCandidates.compressCandidates(countCover, countWords)
    inc reductionRounds
  if countCandidates.len == 0:
    raise newException(ValueError,
      "strings cannot be distinguished by valid byte loads")

  var countSeparatorCounts: seq[int]
  let countPairOrder = separatorOrder(
    countCover, countCandidates.len, countWords, countPairs,
    countSeparatorCounts)
  let greedy = greedyCover(
    countCandidates, countCover, countWords, countPairs)
  let rootLower = rootGainLowerBound(
    countCover, countCandidates.len, countWords, countPairs, greedy.len)

  var minimumCount = 0
  var countOptimum: seq[int]
  var target = rootLower
  while target < greedy.len:
    var smallChosen: seq[int]
    let smallSupported =
      target == 1 or
      (target == 2 and countCandidates.len <= 1024 and
       countCandidates.len * countCandidates.len * countWords <=
         10_000_000) or
      (target == 3 and countCandidates.len <= 512 and
       countCandidates.len * countPairs <= 1_100_000)
    if smallSupported:
      if directSmallCover(
          countCandidates, countCover, countWords, countPairs, target,
          false, smallChosen):
        minimumCount = target
        countOptimum = smallChosen
        break
    else:
      let search = newSearch(
        countCandidates, countCover, countWords, countPairs, target,
        countPairOrder)
      const CountSeparatorIndexWorkLimit = 2_000_000
      if target >= 4 and target <= 5 and countPairs >= 64 and
          countCandidates.len * countPairs <= CountSeparatorIndexWorkLimit:
        search.buildSeparatorIndex(countSeparatorCounts)
      search.exactSearch(0, 0, countPairs, 0)
      if search.stop:
        minimumCount = target
        countOptimum = search.bestChosen
        break
    inc target
  if minimumCount == 0:
    minimumCount = greedy.len
    countOptimum = greedy

  # Secondary search uses every width and a cost-safe kernel.
  var candidates: seq[Candidate]
  var cover: seq[uint64]
  buildCandidates(byteLength, kernelWords, 0,
                  byteCover, candidates, cover)
  var words = kernelWords
  var pairCount = kernelPairCount
  candidates.compressCandidates(cover, words)
  reductionRounds = 0
  while reductionRounds < 8 and reducePairConstraints(
      candidates, cover, pairCount, words):
    candidates.compressCandidates(cover, words)
    inc reductionRounds
  var separatorCounts: seq[int]
  let pairOrder = separatorOrder(
    cover, candidates.len, words, pairCount, separatorCounts)
  var optimum: seq[int]
  var useCountOptimum = false
  if minimumCount == 3 and candidates.len <= 512 and
      candidates.len * pairCount <= 1_100_000:
    discard directThreeTiered(
      candidates, cover, words, pairCount, optimum)
  elif minimumCount == 1 or
      (minimumCount == 2 and candidates.len <= 512 and
       candidates.len * candidates.len * words <= 10_000_000):
    discard directSmallCover(
      candidates, cover, words, pairCount, minimumCount, true, optimum)
  else:
    let byteSearch = newSearch(
      candidates, cover, words, pairCount, minimumCount, pairOrder)
    byteSearch.optimizeBytes = true
    byteSearch.bestBytes = minimumCount * maxWidth + 1
    byteSearch.fillGains(0, 0)
    let rootByteLower = byteSearch.gainWidthLowerBound(
      pairCount, minimumCount, 0)
    if rootByteLower >= minimumCount * maxWidth:
      useCountOptimum = true
    else:
      # The pair-major index costs O(P*C) integers in the worst case. Keep
      # its build and memory bounded, and only pay for it when general search
      # will reach many direct two-slot completions.
      const SeparatorIndexMinWork = 1_000_000
      const SeparatorIndexWorkLimit = 2_000_000
      let separatorWork = candidates.len * pairCount
      let minimumSeparatorWork =
        if minimumCount >= 5:
          0
        else:
          SeparatorIndexMinWork
      if minimumCount >= 4 and pairCount >= 64 and
          separatorWork >= minimumSeparatorWork and
          separatorWork <= SeparatorIndexWorkLimit:
        byteSearch.buildSeparatorIndex(separatorCounts)
      byteSearch.enforcePrefixIrreducible = true
      byteSearch.byteLength = byteLength
      byteSearch.maxWidth = maxWidth
      byteSearch.intervalMarks = newSeq[int](byteLength)
      byteSearch.exactSearch(0, 0, pairCount, 0)
      optimum = byteSearch.bestChosen
  if (useCountOptimum and countOptimum.len != minimumCount) or
      (not useCountOptimum and optimum.len != minimumCount):
    raise newException(AssertionDefect,
      "internal error: byte optimization lost a minimum-count cover")

  result = newSeq[ByteLoad](minimumCount)
  var i = 0
  while i < minimumCount:
    if useCountOptimum:
      result[i] = countCandidates[countOptimum[i]].load
    else:
      result[i] = candidates[optimum[i]].load
    inc i

  # Independent check against all original strings, including removed rows.
  if not uniqueLoadSignatures(strings, result):
    raise newException(AssertionDefect,
      "internal error: exact byte-load cover missed a string pair")

  # Stable presentation order does not affect either objective.
  i = 1
  while i < result.len:
    let item = result[i]
    var j = i
    while j > 0 and item < result[j - 1]:
      result[j] = result[j - 1]
      dec j
    result[j] = item
    inc i

proc distinguishesAll*(strings: openArray[string];
                       loads: openArray[ByteLoad]): bool {.compileTime.} =
  uniqueLoadSignatures(strings, loads)

func objectiveBytes*(loads: openArray[ByteLoad]): int =
  for load in loads:
    result += load.width
