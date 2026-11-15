/** Incremental byte framing. Only a complete protocol line is joined; no
 * workload ceiling, repeated whole-buffer copying or UTF-8 chunk decoding.
 */
export class MCPLineFrames {
  #parts=[];
  #bytes=0;
  get bufferedBytes(){return this.#bytes;}
  push(chunk) {
    const frames=[];
    let offset=0,newline;
    while((newline=chunk.indexOf(0x0a,offset))>=0) {
      const part=chunk.subarray(offset,newline);
      if(this.#bytes) {
        if(part.length)this.#parts.push(part);
        frames.push(Buffer.concat(this.#parts,this.#bytes+part.length));
      } else if(part.length)frames.push(part);
      this.#parts=[];this.#bytes=0;offset=newline+1;
    }
    if(offset<chunk.length) {
      const tail=chunk.subarray(offset);
      this.#parts.push(tail);this.#bytes+=tail.length;
    }
    return frames;
  }
}
