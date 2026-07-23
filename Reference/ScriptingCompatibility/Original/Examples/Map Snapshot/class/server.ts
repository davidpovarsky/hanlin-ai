export type Pin = {
  id: string;
  title: string;
  subtitle: string;
  coordinate: { latitude: number; longitude: number };
  tint: string;
};

class Server {
  pins: Pin[] = [
    {
      id: "shanghai",
      title: "上海",
      subtitle: "中国 · 长江入海口的国际都市",
      coordinate: { latitude: 31.2304, longitude: 121.4737 },
      tint: "systemGreen",
    },
    {
      id: "tokyo",
      title: "东京",
      subtitle: "日本 · 世界上人口最密集的都会区之一",
      coordinate: { latitude: 35.6762, longitude: 139.6503 },
      tint: "systemGreen",
    },
    {
      id: "singapore",
      title: "新加坡",
      subtitle: "东南亚 · 花园城市与重要航运枢纽",
      coordinate: { latitude: 1.3521, longitude: 103.8198 },
      tint: "systemGreen",
    },
  ];

  async getPins() {
    return this.pins;
  }

  getPinById(id: string | null | undefined) {
    if (!id) return null;
    return this.pins.find((pin) => pin.id === id) ?? null;
  }
}

export const server = new Server();
