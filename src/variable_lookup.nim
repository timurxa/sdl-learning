## Public one-file API for variable-length static-string lookup planning.
##
## Import this file only. Sol is an internal compile-time implementation detail.
## Length classes are solved exactly by a cheap interval DP; each class then
## receives the best byte-load cover from the internal solver.

import string_cover as byteCover

type
  ByteLoad* = object
    offset*: int
    width*: int

  LookupClass* = object
    minLength*: int
    maxLength*: int
    stringIndices*: seq[int]
    loads*: seq[ByteLoad]

  LookupPlan* = object
    stringCount*: int
    classes*: seq[LookupClass]

proc orderByLength(strings: openArray[string]; maxLength: int): seq[int]
    {.compileTime.} =
  ## Counting sort is materially cheaper than comparator-based sorting in the
  ## Nim VM.  The fallback keeps behavior sane for unusual huge lengths.
  if maxLength <= 65536:
    var counts = newSeq[int](maxLength + 1)
    for s in strings:
      inc counts[s.len]
    var starts = newSeq[int](maxLength + 1)
    var running = 0
    var length = 0
    while length <= maxLength:
      starts[length] = running
      running += counts[length]
      inc length
    result = newSeq[int](strings.len)
    for index, s in strings:
      result[starts[s.len]] = index
      inc starts[s.len]
  else:
    result = newSeq[int](strings.len)
    for index in 0..<strings.len:
      result[index] = index
    var index = 1
    while index < result.len:
      let item = result[index]
      let itemLength = strings[item].len
      var position = index
      while position > 0 and strings[result[position - 1]].len > itemLength:
        result[position] = result[position - 1]
        dec position
      result[position] = item
      inc index

proc makeLengthGroups(strings: openArray[string]; order: seq[int];
                      groupOf: var seq[int]; lengths: var seq[int];
                      starts: var seq[int]) {.compileTime.} =
  groupOf = newSeq[int](strings.len)
  if order.len == 0:
    starts = @[0]
    return
  var position = 0
  while position < order.len:
    let length = strings[order[position]].len
    lengths.add length
    starts.add position
    let group = lengths.len - 1
    while position < order.len and strings[order[position]].len == length:
      groupOf[order[position]] = group
      inc position
  starts.add order.len

proc chooseLengthStarts(strings: openArray[string]; order, groupOf, lengths,
                        starts: seq[int]): seq[int] {.compileTime.} =
  ## Exact prefix refinement.  For a fixed start group g, classOf is the
  ## equality partition of the active suffix at the previous depth.  Adding
  ## one byte refines it with (old-class, byte), so no pair matrix, hashes, or
  ## repeated prefix copies are needed.
  let groupCount = lengths.len
  if groupCount == 0:
    return @[0]

  var classOf = newSeq[int](strings.len)
  var nextClassOf = newSeq[int](strings.len)
  var stamps = newSeq[int](max(1, strings.len * 256))
  var keyLabels = newSeq[int](stamps.len)
  var classSizes = newSeq[int](max(1, strings.len))
  var generation = 0
  var previousDepth = 0
  var farthest = newSeq[int](groupCount)
  var first = 0
  while first < groupCount:
    let activeStart = starts[first]
    let targetDepth = lengths[first]
    var conflictGroup = groupCount
    var depth = previousDepth
    while depth < targetDepth:
      inc generation
      var classCount = 0
      var item = activeStart
      while item < strings.len:
        let stringIndex = order[item]
        let key = classOf[stringIndex] * 256 +
                  ord(strings[stringIndex][depth])
        var label: int
        if stamps[key] != generation:
          stamps[key] = generation
          label = classCount
          keyLabels[key] = label
          classSizes[label] = 0
          inc classCount
        else:
          label = keyLabels[key]
        if depth + 1 == targetDepth and classSizes[label] != 0 and
            conflictGroup == groupCount:
          conflictGroup = groupOf[stringIndex]
        inc classSizes[label]
        nextClassOf[stringIndex] = label
        inc item
      swap(classOf, nextClassOf)
      inc depth
    if targetDepth == previousDepth:
      var seen = newSeq[int](max(1, strings.len))
      var item = activeStart
      while item < strings.len:
        let label = classOf[order[item]]
        if seen[label] != 0 and conflictGroup == groupCount:
          conflictGroup = groupOf[order[item]]
        inc seen[label]
        inc item
    if conflictGroup == first:
      raise newException(ValueError, "chooseLookupPlan requires distinct strings")
    farthest[first] = if conflictGroup == groupCount:
                        groupCount - 1
                      else:
                        conflictGroup - 1
    previousDepth = targetDepth
    inc first

  ## Farthest endpoints are monotone: removing shorter strings and requiring
  ## a longer common prefix cannot make a later start end earlier.  A deque
  ## therefore solves the interval cover DP in linear time.
  var dp = newSeq[int](groupCount)
  var previous = newSeq[int](groupCount)
  var deque = newSeq[int](groupCount)
  var head = 0
  var tail = 0
  first = 0
  while first < groupCount:
    let prior = if first == 0: 0 else: dp[first - 1]
    while tail > head:
      let back = deque[tail - 1]
      let backCost = if back == 0: 0 else: dp[back - 1]
      if backCost < prior:
        break
      dec tail
    deque[tail] = first
    inc tail
    while head < tail and farthest[deque[head]] < first:
      inc head
    let bestStart = deque[head]
    dp[first] = 1 + (if bestStart == 0: 0 else: dp[bestStart - 1])
    previous[first] = bestStart
    inc first

  var cuts: seq[int]
  var endpoint = groupCount - 1
  while endpoint >= 0:
    let start = previous[endpoint]
    cuts.add endpoint + 1
    endpoint = start - 1
  cuts.add 0
  var left = 0
  var right = cuts.len - 1
  while left < right:
    swap(cuts[left], cuts[right])
    inc left
    dec right
  cuts

proc chooseLengthClasses(strings: openArray[string]): seq[LookupClass]
    {.compileTime.} =
  if strings.len == 0:
    return

  var maxLength = 0
  for s in strings:
    if s.len > maxLength:
      maxLength = s.len
  let order = orderByLength(strings, maxLength)
  var groupOf: seq[int]
  var lengths: seq[int]
  var starts: seq[int]
  makeLengthGroups(strings, order, groupOf, lengths, starts)

  ## Equal-length input already is one valid class; let Sol's inner solver do
  ## its own duplicate validation without paying a second N*B pass.
  let cuts = if lengths.len == 1:
               @[0, 1]
             else:
               chooseLengthStarts(strings, order, groupOf, lengths, starts)
  var cut = 0
  while cut + 1 < cuts.len:
    let firstGroup = cuts[cut]
    let lastGroup = cuts[cut + 1]
    let minLength = lengths[firstGroup]
    var members: seq[int]
    var item = starts[firstGroup]
    while item < starts[lastGroup]:
      let stringIndex = order[item]
      members.add stringIndex
      inc item
    result.add LookupClass(
      minLength: minLength,
      maxLength: lengths[lastGroup - 1],
      stringIndices: members)
    inc cut

proc prefixString(s: string; length: int): string {.compileTime.} =
  if length == s.len:
    return s
  result = newString(length)
  var index = 0
  while index < length:
    result[index] = s[index]
    inc index

proc chooseLookupPlan*(strings: openArray[string]): LookupPlan {.compileTime.} =
  result.stringCount = strings.len
  result.classes = chooseLengthClasses(strings)
  var classIndex = 0
  while classIndex < result.classes.len:
    let classItem = result.classes[classIndex]
    var prefixes: seq[string]
    for stringIndex in classItem.stringIndices:
      prefixes.add prefixString(strings[stringIndex], classItem.minLength)
    let loads = byteCover.chooseByteLoads(prefixes)
    for load in loads:
      doAssert load.offset >= 0
      doAssert load.width == 1 or load.width == 2 or
               load.width == 4 or load.width == 8
      doAssert load.offset + load.width <= classItem.minLength
    var publicLoads = newSeq[ByteLoad](loads.len)
    var loadIndex = 0
    while loadIndex < loads.len:
      publicLoads[loadIndex] = ByteLoad(
        offset: loads[loadIndex].offset,
        width: loads[loadIndex].width)
      inc loadIndex
    result.classes[classIndex].loads = publicLoads
    inc classIndex

func objectiveBytes*(loads: openArray[ByteLoad]): int =
  for load in loads:
    result += load.width

proc distinguishesAll*(strings: openArray[string];
                       loads: openArray[ByteLoad]): bool {.compileTime.} =
  var internalLoads = newSeq[byteCover.ByteLoad](loads.len)
  var index = 0
  while index < loads.len:
    internalLoads[index] = byteCover.ByteLoad(
      offset: loads[index].offset,
      width: loads[index].width)
    inc index
  byteCover.distinguishesAll(strings, internalLoads)

proc lookupIndex*(input: string; strings: openArray[string];
                  plan: LookupPlan): int =
  ## Reference/runtime helper for callers that keep a plan.
  for classItem in plan.classes:
    if input.len >= classItem.minLength and input.len <= classItem.maxLength:
      for index in classItem.stringIndices:
        var equal = strings[index].len == input.len
        if equal:
          var byteIndex = 0
          while byteIndex < input.len:
            if input[byteIndex] != strings[index][byteIndex]:
              equal = false
              break
            inc byteIndex
        if equal:
          return index
      return -1
  -1
