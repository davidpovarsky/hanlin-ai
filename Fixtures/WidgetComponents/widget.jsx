import {VStack,HStack,Text,Button,ProgressView,Gauge,Chart,Image,Link} from '@expo/ui/swift-ui';
import {accessibilityIdentifier,accessibilityLabel,accessibilityValue,containerBackground,font,frame} from '@expo/ui/swift-ui/modifiers';

const observed = (name, label, value) => [
  accessibilityIdentifier('hanlin-component-' + name),
  accessibilityLabel(label),
  accessibilityValue(value),
];

export default function Components(props) {
  'widget';
  const count = props.count ?? 0;
  const current = String(count);
  return <VStack spacing={6} modifiers={[containerBackground('clear','widget'),font({textStyle:'caption'})]}>
    <Text modifiers={observed('count','Components count: ' + current,current)}>{'Components count: ' + current}</Text>
    <Button label="Add" target="increment" onPress={()=>({count:count+1})}
      modifiers={observed('add','Add','Count ' + current)}/>
    <ProgressView value={Math.min(1,count/10)}
      modifiers={observed('progress','Progress count ' + current,current + ' of 10')}>
      <Text>Progress</Text>
    </ProgressView>
    <Gauge value={count} min={0} max={10} currentValueLabel={<Text>{current}</Text>}
      modifiers={observed('gauge','Gauge count ' + current,current + ' of 10')}>
      <Text>Gauge</Text>
    </Gauge>
    <Chart type="bar" data={[{x:'Count',y:count},{x:'Reference',y:10}]}
      modifiers={[...observed('chart','Chart count ' + current,'Count ' + current + '; Reference 10'),frame({height:60})]}/>
    <HStack spacing={12}>
      <Image systemName={count === 0 ? 'book' : 'book.fill'}
        modifiers={observed('symbol','Book count ' + current,count === 0 ? 'Outline book' : 'Filled book')}/>
      <Link destination={'https://example.com/widget-components?count=' + current}
        modifiers={observed('link','Details count ' + current,'Count ' + current)}>
        <Text>Details</Text>
      </Link>
    </HStack>
  </VStack>;
}
