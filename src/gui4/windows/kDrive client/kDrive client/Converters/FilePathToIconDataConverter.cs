using Infomaniak.kDrive.Converters;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Data;
using System;

namespace kDrive_client.Converters;

/// <summary>
/// Converts a file path to the corresponding icon path geometry data (x:String resource).
/// </summary>
public class FilePathToIconDataConverter : IValueConverter
{
    private static readonly FilePathToIconResourceKeyConverter _keyConverter = new();

    public object Convert(object value, Type targetType, object parameter, string language)
    {
        var ressourceKey = _keyConverter.Convert(value, targetType, parameter, language) as string;
        if (string.IsNullOrEmpty(ressourceKey))
            return "";

        // Look up the path data string from application resources
        if (Application.Current.Resources.TryGetValue(ressourceKey, out var pathData))
            return pathData;

        return "";
    }

    public object ConvertBack(object value, Type targetType, object parameter, string language)
        => throw new NotImplementedException();
}