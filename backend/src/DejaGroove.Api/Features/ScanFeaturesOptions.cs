namespace DejaGroove.Api.Features;

public sealed class ScanFeaturesOptions
{
    public const string SectionName = "ScanFeatures";

    public bool UseStubScanRuntime { get; set; }
    public bool EnableResolveEndpoint { get; set; }
}
