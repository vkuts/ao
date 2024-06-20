import { of, fromPromise } from 'hyper-async'

import { pullResultWith } from '../lib/pull-result.js'
import { writeAssignWith } from '../lib/write-assign.js'

/**
 * process an assignment that comes from the cu result endpoint
 *
 * Assignment shape
 * [{ Processes: [ "pid1", "pid2" ], Message: "txid" }]
 */
export function processAssignWith ({
  locateProcess,
  writeAssignment,
  fetchResult,
  logger
}) {
  const writeAssign = writeAssignWith({ writeAssignment, logger })
  const pullResult = pullResultWith({ fetchResult, logger })

  const locateProcessLocal = fromPromise(locateProcess)

  return (ctx) => {
    console.log({ ctx })
    return of(ctx)
      .chain((ctx) => locateProcessLocal(ctx.assign.processId)
        .map((schedLocation) => {
          console.log({ schedLocation })
          return { ...ctx, schedLocation }
        })
      )
      .chain(writeAssign)
      .map((res) => {
        console.log('Jack1', { res })
        return res
      })
      .chain(pullResult)
      .map((res) => {
        console.log('Jack4', { res })
        return res
      })
  }
}
